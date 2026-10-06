@tool
extends Control
## Panneau éditeur Thiossane Deploy
## Copyright (c) 2026 Teranga Game Studio. Tous droits réservés.
## Déploiement direct : fiche jeu, export, ZIP, upload vers Thiossane Store.
##
## Organisation (v1.7.2+) :
##   i18n/strings.gd  — FR / EN / 中文
##   core/constants.gd, core/config.gd
##   core/config.gd utilisé pour tokens (v1.9.2)
##   features/api_client.gd, deploy.gd, profiles.gd, share.gd (v1.9.40)
##   (prochaines extractions : auth, support, notifications…)

const _Strings = preload("res://addons/thiossane_deploy/i18n/strings.gd")
const _Config = preload("res://addons/thiossane_deploy/core/config.gd")
const _Constants = preload("res://addons/thiossane_deploy/core/constants.gd")
const _ApiClient = preload("res://addons/thiossane_deploy/features/api_client.gd")
const _DeployCore = preload("res://addons/thiossane_deploy/features/deploy.gd")
const _Profiles = preload("res://addons/thiossane_deploy/features/profiles.gd")
const _ShareApi = preload("res://addons/thiossane_deploy/features/share.gd")

const CONFIG_SECTION := "thiossane_deploy"
const CONFIG_PATH := "user://thiossane_deploy.cfg"
## Tokens sensibles chiffrés séparément (pas en clair dans le .cfg).
const SECURE_TOKEN_PATH := "user://thiossane_tokens.dat"
const MAX_BUILD_BYTES := 512 * 1024 * 1024  # 512 Mo — aligné backend
const MAX_BUILD_MB := 512
const UPLOAD_CHUNK_SIZE := 4 * 1024 * 1024  # 4 Mo (le serveur peut imposer sa propre taille via chunk_size)

# ── i18n (FR / EN) ────────────────────────────────────────────────────────────
## Langue active : "fr" | "en" | "zh". Auto = locale éditeur, sinon forcée via le bouton.
var _lang: String = "fr"
var _lang_btn: Button
var _ui_title: Label
var _sec_conn: Control
var _sec_game: Control
var _sec_fiche: Control
var _sec_plat: Control
var _sec_deploy: Control
var _sec_prog: Control
var _sec_share: Control
var _sec_support: Control
var support_category: OptionButton
var support_subject_edit: LineEdit
var support_body_edit: TextEdit
var support_submit_btn: Button
var support_list: ItemList
var support_refresh_btn: Button
var support_reply_edit: TextEdit
var support_reply_btn: Button
var support_detail_label: Label
var _support_tickets: Array = []
var _support_selected_id: int = -1
# Notifications in-app (badges sur les sections concernées, pas de section dédiée)
var _notifications: Array = []
var _notif_unread: int = 0
var _notif_poll_timer: Timer
## Clé section → Panel badge (boule rouge)
var _section_badges: Dictionary = {}
## Clé section → nombre de non-lues pour cette section
var _notif_by_section: Dictionary = {}
## Derniers comptes par section (pour ouvrir auto seulement si nouveau)
var _notif_prev_by_section: Dictionary = {}
var game_status_label: Label
var deploy_checklist_label: Label
var _preflight_panel: PanelContainer
var _preflight_label: Label
var _queue_status_label: Label
var _profile_option: OptionButton
var _profile_name_edit: LineEdit
var _profile_save_btn: Button
var _profile_delete_btn: Button
var _resume_upload_btn: Button
var _resume_banner: PanelContainer
var _resume_banner_label: Label
var _deploy_profiles: Dictionary = {}
var _upload_file_sha256: String = ""
var _pending_resume_state: Dictionary = {}
var _hist_label: Label
var _hist_list: ItemList
var _copy_store_btn: Button
var _copy_discord_btn: Button
var _copy_whatsapp_btn: Button
## Historique local des deploys : [{ts, game_id, title, version, platforms, status, note}]
var _deploy_history: Array = []
const DEPLOY_HISTORY_MAX := 40
var redeploy_btn: Button
var _cat_label: Label
var _price_label: Label
var _opt_label: Label
var _log_title: Label
var _clear_log_btn: Button
var _logout_btn: Button
var _refresh_presets_btn: Button
var _footer_label: Label



var _tr_cache: Dictionary = {}
var _tr_cache_lang: String = ""
var _tr_cache_arcade: bool = false


func tr_ui(key: String) -> String:
	if _tr_cache_lang != _lang or _tr_cache_arcade != _arcade_copy:
		_tr_cache.clear()
		_tr_cache_lang = _lang
		_tr_cache_arcade = _arcade_copy
	var cached = _tr_cache.get(key)
	if cached != null:
		return cached
	var res := _tr_ui_uncached(key)
	_tr_cache[key] = res
	return res


func _tr_ui_uncached(key: String) -> String:
	if _arcade_copy:
		var ak := "arcade_" + key
		var av := _Strings.tr_ui(_lang, ak)
		# Si la clé arcade existe (pas un fallback brut sur la clé), l’utiliser
		if av != ak and av != "" and not av.begins_with("["):
			return av
	return _Strings.tr_ui(_lang, key)


## Formatage sûr : évite « not all arguments converted » si placeholders ≠ args.
func _fmt(key: String, args = null) -> String:
	var s := tr_ui(key)
	if args == null:
		return s
	var need := 0
	var i := 0
	while i < s.length():
		if s[i] == "%":
			if i + 1 < s.length() and s[i + 1] == "%":
				i += 2
				continue
			need += 1
			i += 1
			while i < s.length() and s[i] in "0123456789.+- #":
				i += 1
			continue
		i += 1
	var arr: Array = args if typeof(args) == TYPE_ARRAY else [args]
	if need == 0:
		return s
	if arr.size() < need:
		while arr.size() < need:
			arr.append("?")
	elif arr.size() > need:
		arr = arr.slice(0, need)
	return s % arr


func _detect_lang() -> String:
	return _Strings.detect_lang(CONFIG_PATH, CONFIG_SECTION)


func _toggle_lang() -> void:
	_lang = _Strings.next_lang(_lang)
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(CONFIG_SECTION, "lang", _lang)
	cfg.save(CONFIG_PATH)
	_apply_ui_texts()


func _apply_ui_texts() -> void:
	if is_instance_valid(_ui_title):
		_ui_title.text = tr_ui("title")
	if is_instance_valid(_conn_label) and access_token == "":
		_conn_label.text = tr_ui("not_connected")
	if is_instance_valid(user_label) and access_token == "":
		user_label.visible = false
		user_label.text = ""
	if is_instance_valid(_status_banner_label) and access_token == "":
		_status_banner_label.text = tr_ui("login_to_start")
	if is_instance_valid(_onboarding_title):
		_onboarding_title.text = tr_ui("ob_title")
	if is_instance_valid(_onboarding_skip_btn):
		_onboarding_skip_btn.text = tr_ui("ob_skip")
	if is_instance_valid(_onboarding_dismiss_btn):
		_onboarding_dismiss_btn.text = tr_ui("ob_dismiss")
	if is_instance_valid(_game_empty_label):
		_game_empty_label.text = tr_ui("ob_game_empty")
	_refresh_onboarding()
	if is_instance_valid(api_base_edit):
		api_base_edit.placeholder_text = tr_ui("api_ph")
	if is_instance_valid(email_edit):
		email_edit.placeholder_text = tr_ui("email_ph")
	if is_instance_valid(password_edit):
		password_edit.placeholder_text = tr_ui("password_ph")
	if is_instance_valid(connect_btn):
		connect_btn.text = tr_ui("connect")
		connect_btn.tooltip_text = tr_ui("connect_tip")
	if is_instance_valid(_logout_btn):
		_logout_btn.text = tr_ui("logout")
		_logout_btn.tooltip_text = tr_ui("logout_tip")
	if is_instance_valid(game_option):
		game_option.tooltip_text = tr_ui("game_tip")
	if is_instance_valid(refresh_games_btn):
		refresh_games_btn.text = tr_ui("refresh_games")
		refresh_games_btn.tooltip_text = tr_ui("refresh_games_tip")
	if is_instance_valid(title_edit):
		title_edit.placeholder_text = tr_ui("title_ph")
	if is_instance_valid(version_edit):
		version_edit.placeholder_text = tr_ui("version_ph")
		version_edit.tooltip_text = tr_ui("version_tip")
	if is_instance_valid(desc_edit):
		desc_edit.placeholder_text = tr_ui("desc_ph")
	if is_instance_valid(_cat_label):
		_cat_label.text = tr_ui("category")
	if is_instance_valid(_price_label):
		_price_label.text = tr_ui("price")
	if is_instance_valid(free_check):
		free_check.text = tr_ui("free")
	if is_instance_valid(demo_check):
		demo_check.text = tr_ui("demo")
	if is_instance_valid(browser_check):
		browser_check.text = tr_ui("browser")
		browser_check.tooltip_text = tr_ui("browser_tip")
	if is_instance_valid(_opt_label):
		_opt_label.text = tr_ui("optional")
	if is_instance_valid(release_edit):
		release_edit.placeholder_text = tr_ui("release_ph")
	if is_instance_valid(cover_edit):
		cover_edit.placeholder_text = tr_ui("cover_ph")
	if is_instance_valid(create_game_btn):
		create_game_btn.text = tr_ui("save_fiche")
		create_game_btn.tooltip_text = tr_ui("save_fiche_tip")
	if is_instance_valid(preset_web):
		preset_web.tooltip_text = tr_ui("preset_web_tip")
	if is_instance_valid(preset_windows):
		preset_windows.tooltip_text = tr_ui("preset_win_tip")
	if is_instance_valid(preset_android):
		preset_android.tooltip_text = tr_ui("preset_and_tip")
	if is_instance_valid(_refresh_presets_btn):
		_refresh_presets_btn.text = tr_ui("refresh_presets")
	if is_instance_valid(deploy_btn):
		deploy_btn.text = tr_ui("deploy")
		deploy_btn.tooltip_text = tr_ui("deploy_tip")
	if is_instance_valid(redeploy_btn):
		redeploy_btn.text = tr_ui("redeploy")
		redeploy_btn.tooltip_text = tr_ui("redeploy_tip")
	if is_instance_valid(resubmit_btn):
		resubmit_btn.text = tr_ui("resubmit")
		resubmit_btn.tooltip_text = tr_ui("resubmit_tip")
	_refresh_game_status_ui()
	_update_deploy_checklist()
	if is_instance_valid(step_label) and not is_busy:
		step_label.text = tr_ui("step_idle")
	if is_instance_valid(_log_title):
		_log_title.text = tr_ui("journal")
	if is_instance_valid(_clear_log_btn):
		_clear_log_btn.text = tr_ui("clear_log")
		_clear_log_btn.tooltip_text = tr_ui("clear_log_tip")
	if is_instance_valid(log_edit):
		log_edit.placeholder_text = tr_ui("log_ph")
	if is_instance_valid(_footer_label):
		_footer_label.text = tr_ui("footer")
	if is_instance_valid(_lang_btn):
		_lang_btn.text = tr_ui("lang_btn")
		_lang_btn.tooltip_text = tr_ui("lang_tip")
	if is_instance_valid(_theme_option):
		_theme_option.tooltip_text = tr_ui("theme_tip")
		# Doit matcher exactement l'ordre des add_item() dans _build_ui
		var labels := [
			tr_ui("theme_circe"), tr_ui("theme_sakura"), tr_ui("theme_onyx"),
			tr_ui("theme_ivory"), tr_ui("theme_ember"), tr_ui("theme_matrix"),
			tr_ui("theme_forest"), tr_ui("theme_ps2"), tr_ui("theme_underground"),
			tr_ui("theme_chicago30"), tr_ui("theme_gangster90"), tr_ui("theme_gangsta00"),
			tr_ui("theme_teranga"), tr_ui("theme_wax"), tr_ui("theme_sahel"),
			tr_ui("theme_savane"), tr_ui("theme_synthwave"), tr_ui("theme_cyberpunk"),
			tr_ui("theme_steampunk"), tr_ui("theme_horror"), tr_ui("theme_minimal"),
			tr_ui("theme_pixel"), tr_ui("theme_vaporwave"),
			tr_ui("theme_manga"), tr_ui("theme_ocean"), tr_ui("theme_brutalist"),
			tr_ui("theme_western"), tr_ui("theme_comicbook"), tr_ui("theme_custom")
		]
		for i in range(mini(_theme_option.item_count, labels.size())):
			_theme_option.set_item_text(i, labels[i])
	if is_instance_valid(_theme_edit_btn):
		_theme_edit_btn.tooltip_text = tr_ui("theme_edit_tip")
	if is_instance_valid(_crt_btn):
		_crt_btn.text = "CRT" if _crt_enabled else "crt"
		_crt_btn.tooltip_text = tr_ui("crt_tip")
	if is_instance_valid(_neon_btn):
		_neon_btn.text = "NEON" if _neon_enabled else "neon"
		_neon_btn.tooltip_text = tr_ui("neon_tip")
	if is_instance_valid(_predator_btn):
		_predator_btn.text = "PREDATOR" if _predator_enabled else "Predator"
		_predator_btn.tooltip_text = tr_ui("predator_tip")
	if is_instance_valid(_rain_btn):
		_rain_btn.text = "RAIN" if _rain_enabled else "Rain"
		_rain_btn.tooltip_text = tr_ui("rain_tip")
	if is_instance_valid(_paper_btn):
		_paper_btn.text = "PAPER" if _paper_enabled else "Paper"
		_paper_btn.tooltip_text = tr_ui("paper_tip")
	if is_instance_valid(_arcade_btn):
		_arcade_btn.text = "ARCADE" if _arcade_copy else "arcade"
		_arcade_btn.tooltip_text = tr_ui("arcade_tip")
	if is_instance_valid(_sfx_btn):
		_sfx_btn.text = "SFX" if _sfx_enabled else "sfx"
		_sfx_btn.tooltip_text = tr_ui("sfx_tip")
	if is_instance_valid(_tag_btn):
		_tag_btn.text = "TAG ✎" if _tag_draw_mode else "tag"
		_tag_btn.tooltip_text = tr_ui("tag_tip")
	if is_instance_valid(_coffee_btn):
		_coffee_btn.text = tr_ui("break_btn")
		_coffee_btn.tooltip_text = tr_ui("break_tip")
	if is_instance_valid(_chaos_btn):
		_chaos_btn.text = tr_ui("chaos_btn")
		_chaos_btn.tooltip_text = tr_ui("chaos_tip")
	if is_instance_valid(_cozy_btn):
		_cozy_btn.text = tr_ui("cozy_on") if _cozy_mode else tr_ui("cozy_btn")
		_cozy_btn.tooltip_text = tr_ui("cozy_tip")
		_cozy_btn.button_pressed = _cozy_mode
	_comfort_refresh_greeting()
	if is_instance_valid(_music_pick_btn):
		_music_pick_btn.text = tr_ui("music_pick")
		_music_pick_btn.tooltip_text = tr_ui("music_tip")
	if is_instance_valid(_music_play_btn):
		_music_play_btn.tooltip_text = tr_ui("music_tip")
	if is_instance_valid(_music_stop_btn):
		_music_stop_btn.text = tr_ui("music_stop")
	if is_instance_valid(_music_loop_check):
		_music_loop_check.text = tr_ui("music_loop")
	if is_instance_valid(_music_mute_check):
		_music_mute_check.text = tr_ui("music_mute")
	_set_section_text(_sec_music, tr_ui("music_sec"))
	_music_sync_ui()
	if is_instance_valid(_music_pl_label):
		_music_pl_label.text = tr_ui("music_playlist")
	if is_instance_valid(_music_add_btn):
		_music_add_btn.text = tr_ui("music_pl_add")
		_music_add_btn.tooltip_text = tr_ui("music_pl_add_tip")
	if is_instance_valid(_music_remove_btn):
		_music_remove_btn.text = tr_ui("music_pl_remove")
		_music_remove_btn.tooltip_text = tr_ui("music_pl_remove_tip")
	if is_instance_valid(_music_clear_pl_btn):
		_music_clear_pl_btn.text = tr_ui("music_pl_clear")
		_music_clear_pl_btn.tooltip_text = tr_ui("music_pl_clear_tip")
	if is_instance_valid(_music_prev_btn):
		_music_prev_btn.text = tr_ui("music_prev")
		_music_prev_btn.tooltip_text = tr_ui("music_prev_tip")
	if is_instance_valid(_music_next_btn):
		_music_next_btn.text = tr_ui("music_next")
		_music_next_btn.tooltip_text = tr_ui("music_next_tip")
	_music_playlist_refresh_ui()
	if is_instance_valid(_cozy_btn):
		_cozy_btn.button_pressed = _cozy_mode
		_apply_cozy_mode(false)
	if is_instance_valid(_video_pick_btn):
		_video_pick_btn.text = tr_ui("video_pick")
		_video_pick_btn.tooltip_text = tr_ui("video_tip")
	if is_instance_valid(_video_play_btn):
		_video_play_btn.text = tr_ui("video_play") if not (is_instance_valid(_video_player) and _video_player.is_playing()) else tr_ui("video_pause")
	if is_instance_valid(_video_stop_btn):
		_video_stop_btn.text = tr_ui("video_stop")
	if is_instance_valid(_video_loop_check):
		_video_loop_check.text = tr_ui("video_loop")
	if is_instance_valid(_video_hint):
		_video_hint.text = tr_ui("video_hint")
	if is_instance_valid(_video_open_os_btn):
		_video_open_os_btn.text = tr_ui("video_open_os")
		_video_open_os_btn.tooltip_text = tr_ui("video_open_os_tip")
	_set_section_text(_sec_video, tr_ui("video_sec"))
	_video_sync_ui()
	if is_instance_valid(store_base_edit):
		store_base_edit.placeholder_text = tr_ui("store_base_ph")
		store_base_edit.tooltip_text = tr_ui("store_base_tip")
	if is_instance_valid(share_label_edit):
		share_label_edit.placeholder_text = tr_ui("share_label_ph")
	if is_instance_valid(campaign_edit):
		campaign_edit.placeholder_text = tr_ui("campaign_ph")
	if is_instance_valid(channel_edit):
		channel_edit.placeholder_text = tr_ui("channel_ph")
	if is_instance_valid(share_force_check):
		share_force_check.text = tr_ui("share_force_new")
	if is_instance_valid(share_generate_btn):
		share_generate_btn.text = tr_ui("share_generate")
		share_generate_btn.tooltip_text = tr_ui("share_generate_tip")
	if is_instance_valid(share_copy_link_btn):
		share_copy_link_btn.text = tr_ui("share_copy_link")
	if is_instance_valid(_copy_store_btn):
		_copy_store_btn.text = tr_ui("link_store")
		_copy_store_btn.tooltip_text = tr_ui("link_store_tip")
	if is_instance_valid(_copy_discord_btn):
		_copy_discord_btn.text = tr_ui("link_discord")
		_copy_discord_btn.tooltip_text = tr_ui("link_discord_tip")
	if is_instance_valid(_copy_whatsapp_btn):
		_copy_whatsapp_btn.text = tr_ui("link_whatsapp")
		_copy_whatsapp_btn.tooltip_text = tr_ui("link_whatsapp_tip")
	if is_instance_valid(_hist_label):
		_hist_label.text = tr_ui("hist_title")
	if is_instance_valid(share_stats_btn):
		share_stats_btn.text = tr_ui("share_stats_refresh")
	if is_instance_valid(mkt_analytics_btn):
		mkt_analytics_btn.text = tr_ui("mkt_analytics")
		mkt_analytics_btn.tooltip_text = tr_ui("mkt_analytics_tip")
	if is_instance_valid(build_limit_label):
		build_limit_label.text = tr_ui("build_limit") % MAX_BUILD_MB
	if is_instance_valid(share_url_edit) and _current_share.is_empty():
		share_url_edit.placeholder_text = tr_ui("share_empty")
	_update_section_headers()
	# Mascotte : réadapter la réplique à la langue active si elle est visible
	if _mascot_visible and is_instance_valid(_mascot_bubble_label):
		_mascot_bubble_label.text = _mascot_pick_line(false)
		_mascot_apply_bubble_size()
		if is_instance_valid(_mascot_root):
			_mascot_root.reset_size()
			_mascot_root.position = _mascot_bottom_right()


func _update_section_headers() -> void:
	_set_section_text(_sec_conn, tr_ui("sec_conn"))
	_set_section_text(_sec_game, tr_ui("sec_game"))
	_set_section_text(_sec_fiche, tr_ui("sec_fiche"))
	_set_section_text(_sec_plat, tr_ui("sec_plat"))
	_set_section_text(_sec_deploy, tr_ui("sec_deploy"))
	_set_section_text(_sec_prog, tr_ui("sec_prog"))
	_set_section_text(_sec_share, tr_ui("sec_share"))
	_set_section_text(_sec_support, tr_ui("sec_support"))
	_support_fill_categories()


func _set_section_text(box: Control, text: String) -> void:
	if not is_instance_valid(box):
		return
	if box.has_meta("header_btn"):
		var btn: Button = box.get_meta("header_btn")
		if is_instance_valid(btn):
			btn.set_meta("sec_title", text)
			_refresh_section_header(btn)
		return
	for c in box.get_children():
		if c is Label:
			(c as Label).text = text
			return
		if c is Button:
			(c as Button).set_meta("sec_title", text)
			_refresh_section_header(c as Button)
			return


# ── État ──────────────────────────────────────────────────────────────────────
var access_token: String = ""
var refresh_token: String = ""
var current_user: Dictionary = {}
var categories: Array = []
var my_games: Array = []
var selected_game_id: int = -1
## Statut courant du jeu sélectionné (nécessaire pour les PUT partiels :
## sans ce champ, le backend dénormalise status=draft par défaut → 403).
var selected_game_status: String = "draft"
var is_busy: bool = false
var _my_games_tried_fallback: bool = false
var _refreshing_token: bool = false
var _retry_after_refresh: Dictionary = {}  # {method, path, body, kind} pour rejouer après refresh

# ── Ship streak (persistant) ─────────────────────────────────────────────────
var _ship_total: int = 0
var _ship_week_count: int = 0
var _ship_week_key: String = ""  # "YYYY-WW"
const MAX_UPLOAD_WARN_MB := 200.0

# ── UI refs ───────────────────────────────────────────────────────────────────
var api_base_edit: LineEdit
var email_edit: LineEdit
var password_edit: LineEdit
var connect_btn: Button
var status_label: Label
var user_label: Label

var title_edit: LineEdit
var desc_edit: TextEdit
var category_option: OptionButton
var price_edit: SpinBox
var free_check: CheckBox
var demo_check: CheckBox
var browser_check: CheckBox
var release_edit: LineEdit
var cover_edit: LineEdit
var version_edit: LineEdit

var platform_web: CheckBox
var platform_windows: CheckBox
var platform_android: CheckBox

var preset_web: OptionButton
var preset_windows: OptionButton
var preset_android: OptionButton

var game_option: OptionButton
var create_game_btn: Button
var deploy_btn: Button
var resubmit_btn: Button
var refresh_games_btn: Button

var progress_bar: ProgressBar
var log_edit: TextEdit
var step_label: Label

# Feedback UI — messages locaux près de chaque zone d'action
var _status_banner: PanelContainer
var _status_banner_label: Label
var _conn_dot: Panel
var _conn_label: Label
var _feedback_timer: Timer
var _fb_auth: PanelContainer
var _fb_auth_label: Label
var _fb_fiche: PanelContainer
var _fb_fiche_label: Label
var _fb_deploy: PanelContainer
var _fb_deploy_label: Label
## Zone active pour le prochain feedback : "auth" | "fiche" | "deploy" | "all"
var _fb_zone: String = "all"
var _scroll: ScrollContainer

# Palette runtime (thèmes commutables) — défaut Circe (esthétique Asereth / rouge profond)
var C_PRIMARY := Color(0.86, 0.14, 0.22)
var C_PRIMARY_FG := Color(0.98, 0.95, 0.94)
var C_ACCENT := Color(0.95, 0.82, 0.78)
var C_SURFACE := Color(0.14, 0.05, 0.07)
var C_CARD := Color(0.10, 0.03, 0.05)
var C_BORDER := Color(0.42, 0.12, 0.18)
var C_OK := Color(0.35, 0.78, 0.52)
var C_ERR := Color(0.95, 0.40, 0.42)
var C_WARN := Color(0.86, 0.14, 0.22)
var C_INFO := Color(0.86, 0.14, 0.22)
var C_MUTED := Color(0.68, 0.48, 0.52)
var C_IDLE := Color(0.68, 0.48, 0.52)
var C_BUSY := Color(0.86, 0.14, 0.22)
var C_BANNER_OK := Color(0.10, 0.22, 0.16, 0.95)
var C_BANNER_ERR := Color(0.28, 0.12, 0.12, 0.95)
var C_BANNER_WARN := Color(0.26, 0.12, 0.12, 0.95)
var C_BANNER_INFO := Color(0.14, 0.05, 0.07, 0.95)
var C_BANNER_IDLE := Color(0.09, 0.03, 0.04, 0.94)
var C_SECTION := Color(0.86, 0.14, 0.22)
var C_TEXT := Color(0.98, 0.94, 0.92)
var C_HOVER_SURFACE := Color(0.20, 0.07, 0.10)
var C_PRESSED_SURFACE := Color(0.08, 0.02, 0.04)

## Thème actif : default | matrix | sunrise | forest | sepia
var _ui_theme: String = "circe"
var _theme_option: OptionButton
var _theme_edit_btn: Button
## Shape / style params (personnalisables)
var _t_radius_card: int = 14
var _t_radius_btn: int = 12
var _t_radius_field: int = 11
var _t_border_w: int = 1
var _t_shadow_size: int = 6
var _t_shadow_alpha: float = 0.22
var _t_font_delta: int = 0
## PS2 / underground
var _crt_enabled: bool = false
var _neon_enabled: bool = false
var _neon_intensity: float = 0.7
var _neon_pulse_t: float = 0.0
var _neon_btn: Button = null
var _neon_slider: HSlider = null
var _neon_toolbar: PanelContainer = null
var _crt_intensity: float = 0.35  # 0..1 — force globale CRT
var _crt_intensity_slider: HSlider = null
var _crt_toolbar: PanelContainer = null
var _crt_motion: bool = false
var _arcade_copy: bool = false
var _sfx_enabled: bool = false
var _crt_layer: Control = null
var _crt_scan: TextureRect = null
var _crt_grain: TextureRect = null
var _crt_phosphor: TextureRect = null
var _crt_vignette: ColorRect = null
var _crt_roll: ColorRect = null
var _crt_aberr_r: ColorRect = null
var _crt_aberr_b: ColorRect = null
var _crt_flicker_t: float = 0.0
var _crt_roll_y: float = 0.0
## Overlays ambiance : Predator (thermique), Rain, Paper/halftone
var _predator_enabled: bool = false
var _predator_intensity: float = 0.45
var _predator_btn: Button = null
var _predator_layer: Control = null
var _predator_heat: TextureRect = null
var _predator_scan: ColorRect = null
var _predator_t: float = 0.0
var _rain_enabled: bool = false
var _rain_intensity: float = 0.5
var _rain_btn: Button = null
var _rain_layer: Control = null
var _rain_tex: TextureRect = null
var _rain_offset: float = 0.0
var _paper_enabled: bool = false
var _paper_intensity: float = 0.4
var _paper_btn: Button = null
var _paper_layer: Control = null
var _paper_grain: TextureRect = null
var _paper_tone: TextureRect = null
## Ambiance de fond par univers (derrière le contenu)
var _theme_bg_layer: Control = null
var _theme_bg_base: ColorRect = null
var _theme_bg_pattern: TextureRect = null
var _theme_bg_accent: TextureRect = null
var _theme_bg_vignette: ColorRect = null
var _theme_bg_id: String = ""
var _graffiti_layer: Control = null
var _sfx_player: AudioStreamPlayer = null
var _arcade_btn: Button
var _crt_btn: Button
var _sfx_btn: Button
var _fx_toggle_btn: Button = null
var _fx_panel: PanelContainer = null
var _fx_panel_open: bool = false
var _graffiti_timer: Timer = null
## Dessin graffiti libre sur le dock
var _tag_draw_mode: bool = false
var _tag_btn: Button
var _tag_canvas: Control = null
var _tag_tex_rect: TextureRect = null
var _tag_image: Image = null
var _tag_texture: ImageTexture = null
var _tag_drawing: bool = false
var _tag_last_pos: Vector2 = Vector2.ZERO
var _tag_brush_size: float = 10.0
var _tag_color: Color = Color(0.95, 0.2, 0.15, 0.85)
var _tag_toolbar: PanelContainer = null
var _tag_size_slider: HSlider = null
var _tag_dirty: bool = false
var _tag_flush_acc: float = 0.0
var _spray_tex_cache: Dictionary = {}
## RenderWare-era 3D look
## Presets utilisateur nommés : { "Mon thème": {palette+shape} }
var _user_themes: Dictionary = {}
var _theme_editor_layer: Control = null
var _te_color_pickers: Dictionary = {}  # key -> ColorPickerButton
var _te_spins: Dictionary = {}  # key -> SpinBox
var _te_fx_checks: Dictionary = {}  # key -> CheckButton
var _te_fx_spins: Dictionary = {}  # key -> HSlider
var _te_name_edit: LineEdit
var _te_preset_option: OptionButton
var _coffee_btn: Button
var _music_path: String = ""
var _music_player: AudioStreamPlayer
var _music_file_dialog: EditorFileDialog
var _music_label: Label
var _music_play_btn: Button
var _music_stop_btn: Button
var _music_pick_btn: Button
var _music_loop_check: CheckBox
var _music_mute_check: CheckBox
var _music_seek: HSlider
var _music_vol: HSlider
var _music_rate: OptionButton
var _music_time_label: Label
var _music_seeking: bool = false
var _music_volume_db: float = -6.0
var _music_loop: bool = true
var _music_duration: float = 0.0
var _music_playlist: Array = []  # chemins absolus
var _music_pl_index: int = -1
var _music_playlist_list: ItemList
var _music_prev_btn: Button
var _music_next_btn: Button
var _music_add_btn: Button
var _music_remove_btn: Button
var _music_clear_pl_btn: Button
var _music_pl_label: Label
var _sec_music: Control
# ── Lecteur vidéo (section Avancé) ───────────────────────────────────────────
var _sec_video: Control
var _video_player: VideoStreamPlayer
var _video_path: String = ""
var _video_label: Label
var _video_hint: Label
var _video_play_btn: Button
var _video_stop_btn: Button
var _video_pick_btn: Button
var _video_loop_check: CheckBox
var _video_vol: HSlider
var _video_seek: HSlider
var _video_time_label: Label
var _video_file_dialog: EditorFileDialog
var _video_seeking: bool = false
var _video_loop: bool = false
var _video_volume: float = 1.0
var _video_open_os_btn: Button
var _quote_shown_day: String = ""
var _coffee_layer: Control
var _coffee_active: bool = false
## Chaos FX (exploser / brûler / geler l’UI)
var _chaos_btn: Button
var _chaos_layer: Control
var _chaos_active: bool = false
var _chaos_kind: String = ""
var _chaos_saved: Array = []  # {node, modulate, position, rotation, scale}
var _chaos_smoke: CPUParticles2D
var _chaos_embers: CPUParticles2D
var _chaos_timer: SceneTreeTimer
var _chaos_tweens: Array = []  # Tween actifs à tuer avant restore (évite UI noire après burn)
## Personnalisation Chaos FX
var _chaos_intensity: float = 1.0  # 0.6 | 1.0 | 1.5
var _chaos_duration_mult: float = 1.0  # 0.7 | 1.0 | 1.4
var _chaos_particles: bool = true
var _chaos_auto_restore: bool = true
var _chaos_shake: bool = true
var _chaos_emojis: bool = true
var _chaos_on_success: bool = true  # proposer / auto soft Chaos après deploy réussi
var _chaos_opt_intensity: OptionButton
var _chaos_opt_duration: OptionButton
var _chaos_chk_particles: CheckBox
var _chaos_chk_auto: CheckBox
var _chaos_chk_shake: CheckBox
var _chaos_chk_emojis: CheckBox
var _chaos_chk_on_success: CheckBox
var _celeb_chaos_btn: Button
var _chaos_hint_shown_this_busy: bool = false
var _coffee_cup: Node3D
var _coffee_steam: GPUParticles3D
var _coffee_glow: OmniLight3D
var _coffee_heat: float = 0.0
var _break_kind: String = "coffee"  # coffee | cola | pizza | cigarette | marijuana
var _break_warn_label: Label
var _break_msg_label: Label
var _break_phase: float = 0.0  # 0→1 progression de l'expérience
var _break_sip_t: float = 0.0  # temps pour gestes rythmés (gorgée / bouffée)
var _cozy_mode: bool = false
var _cozy_btn: Button
var _greet_label: Label
var _tip_label: Label
var _tip_timer: Timer
var _busy_tip_timer: Timer
var _tip_index: int = 0
var _session_start_sec: float = 0.0
var _festive_enabled: bool = true
var _festive_id: String = ""  # "" | winter | korite | tabaski | independence
var _festive_layer: Control
var _festive_banner: Label
var _snow_particles: CPUParticles2D
var _garland_bar: HBoxContainer

# Layout responsive
var _root_vbox: VBoxContainer
var _content_root: VBoxContainer
var _content_margin: MarginContainer
var _header_block: VBoxContainer
var _header_tools: FlowContainer
var _row_auth: BoxContainer
var _row_title_ver: BoxContainer
var _row_cat_price: BoxContainer
var _row_checks: BoxContainer
var _row_actions: BoxContainer
var _plat_grid: VBoxContainer
var _layout_narrow: bool = false
const LAYOUT_NARROW_PX := 340.0
const LAYOUT_COMPACT_PX := 280.0

var http: HTTPRequest
var upload_http: HTTPRequest

# Share link UI
var store_base_edit: LineEdit
var share_label_edit: LineEdit
var share_force_check: CheckBox
var share_generate_btn: Button
var share_copy_link_btn: Button
var share_stats_btn: Button
var campaign_edit: LineEdit
var channel_edit: LineEdit
var mkt_analytics_btn: Button
var mkt_sales_label: Label
var build_limit_label: Label
var _upload_session_uuid: String = ""
var _upload_chunks_total: int = 0
var _upload_chunk_index: int = 0
var _upload_file_path: String = ""
var _upload_platform: String = ""
var _upload_chunk_size: int = UPLOAD_CHUNK_SIZE
## Progression fine (Mo/s, ETA, reprise)
var _upload_total_bytes: int = 0
var _upload_bytes_done: int = 0  # octets déjà pris en compte (y compris reprise)
var _upload_speed_ema: float = 0.0  # octets / seconde
var _upload_chunk_started_msec: int = 0
var _upload_chunk_bytes: int = 0
var _upload_is_resume: bool = false
var upload_detail_label: Label
## Onboarding première session
var _onboarding_done: bool = false
var _onboarding_panel: PanelContainer
var _onboarding_title: Label
var _onboarding_next: Label
var _onboarding_steps_box: VBoxContainer
var _onboarding_step_btns: Array = []  # Button x5
var _onboarding_skip_btn: Button
var _onboarding_dismiss_btn: Button
var _game_empty_label: Label
var _secure_key: PackedByteArray
var share_url_edit: LineEdit
var share_stats_label: Label
var _current_share: Dictionary = {}  # last share-link payload

# Ambassadeurs (liens ciblés par email)
var amb_email_edit: LineEdit
var amb_label_edit: LineEdit
var amb_invite_check: CheckBox
var amb_generate_btn: Button
var amb_copy_btn: Button
var amb_stats_btn: Button
var amb_url_edit: LineEdit
var amb_stats_label: Label
var _current_ambassador: Dictionary = {}


## Taille de police de l'éditeur Godot (même que le reste de l'UI).
## Suit Réglages éditeur → Interface → Éditeur → Taille de police principale.
func _ed_font(delta: int = 0) -> int:
	var base := 16
	if Engine.is_editor_hint():
		var theme: Theme = EditorInterface.get_editor_theme()
		if theme != null:
			if theme.has_font_size("main_size", "EditorFonts"):
				base = theme.get_font_size("main_size", "EditorFonts")
			elif theme.has_font_size("font_size", "Editor"):
				base = theme.get_font_size("font_size", "Editor")
			elif theme.default_font_size > 0:
				base = theme.default_font_size
	return maxi(base + delta, 11)


func _apply_font(ctrl: Control, delta: int = 0) -> void:
	if is_instance_valid(ctrl):
		ctrl.add_theme_font_size_override("font_size", _ed_font(delta))


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(260, 200)
	clip_contents = true
	_lang = _detect_lang()
	# 1) UI de base uniquement — aucun effet lourd ici
	_build_ui()
	_load_config()
	# 2) Sync toggles (sans créer d'overlays tout de suite)
	if is_instance_valid(_crt_btn):
		_crt_btn.button_pressed = _crt_enabled
	if is_instance_valid(_neon_btn):
		_neon_btn.button_pressed = _neon_enabled
	if is_instance_valid(_arcade_btn):
		_arcade_btn.button_pressed = _arcade_copy
	if is_instance_valid(_sfx_btn):
		_sfx_btn.button_pressed = _sfx_enabled
	if is_instance_valid(_tag_btn):
		_tag_btn.button_pressed = _tag_draw_mode
	_refresh_presets()
	_load_deploy_profiles()
	call_deferred("_check_pending_upload_resume")
	resized.connect(_on_panel_resized)
	call_deferred("_on_panel_resized")
	# 3) Effets / mascotte / comfort — frame suivante (évite crash à l'ouverture d'onglet)
	call_deferred("_boot_deferred_fx")
	_session_start_sec = Time.get_unix_time_from_system()
	call_deferred("_comfort_refresh_greeting")
	call_deferred("_on_comfort_tip_tick")
	call_deferred("_refresh_onboarding")
	call_deferred("_festive_apply")
	call_deferred("_night_focus_apply")
	if access_token != "":
		_log(tr_ui("session_prev"), "info")
		_feedback(tr_ui("login_to_start"), "idle")  # ne bloque pas le boot sur réseau
		call_deferred("_boot_session_check")
	else:
		_feedback(tr_ui("login_to_start"), "idle")


func _boot_deferred_fx() -> void:
	## Après le premier frame — overlays optionnels seulement si activés
	if not is_inside_tree():
		return
	# Mascotte soft
	if not is_instance_valid(_mascot_layer):
		_setup_mascot()
	call_deferred("_maybe_show_quote_of_the_day")
	# Overlays : uniquement si l'utilisateur les a explicitement activés
	if _crt_enabled:
		_ensure_crt_overlay()
	if _predator_enabled:
		_ensure_predator_overlay()
	if _rain_enabled:
		_ensure_rain_overlay()
	if _paper_enabled:
		_ensure_paper_overlay()
	# Canvas tag seulement si mode tag déjà on (évite Image RGBA plein dock au boot)
	if _tag_draw_mode:
		_tag_ensure_canvas()
	set_process(_fx_needs_process())


func _boot_session_check() -> void:
	if access_token == "":
		return
	_feedback(tr_ui("session_check"), "busy")
	_set_busy(true)
	_request_me()



# ══════════════════════════════════════════════════════════════════════════════
# UI CONSTRUCTION
# ══════════════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	# --- Conteneur scroll responsive (dock droit = étroit) ---
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.clip_contents = true
	add_child(_scroll)

	_root_vbox = VBoxContainer.new()
	_root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_vbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_root_vbox.add_theme_constant_override("separation", 10)
	# Largeur min 0 → le contenu suit la largeur du dock (pas de débordement horizontal)
	_root_vbox.custom_minimum_size = Vector2(0, 0)
	_scroll.add_child(_root_vbox)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	_root_vbox.add_child(margin)
	_content_margin = margin

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)
	_content_root = root

	# ── HEADER (titre + outils en FlowContainer = wrap auto) ─────────────────
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(header)
	_header_block = header

	var title := Label.new()
	title.text = tr_ui("title")
	title.add_theme_font_size_override("font_size", _ed_font(4))
	title.add_theme_color_override("font_color", C_PRIMARY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(title)
	_ui_title = title

	# Barre d’outils qui passe à la ligne si le dock est étroit
	_header_tools = HFlowContainer.new()
	_header_tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_tools.add_theme_constant_override("h_separation", 6)
	_header_tools.add_theme_constant_override("v_separation", 6)
	_header_tools.alignment = FlowContainer.ALIGNMENT_CENTER
	header.add_child(_header_tools)

	# Sélecteur de langue FR / EN / 中文
	_lang_btn = Button.new()
	_lang_btn.text = tr_ui("lang_btn")
	_lang_btn.tooltip_text = tr_ui("lang_tip")
	_lang_btn.custom_minimum_size = Vector2(40, 0)
	_lang_btn.pressed.connect(_toggle_lang)
	_header_tools.add_child(_lang_btn)
	_style_secondary_button(_lang_btn)

	_theme_option = OptionButton.new()
	_theme_option.tooltip_text = tr_ui("theme_tip")
	_theme_option.custom_minimum_size = Vector2(100, 0)
	_theme_option.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_theme_option.add_item(tr_ui("theme_circe"), 0)
	_theme_option.set_item_metadata(0, "circe")
	_theme_option.add_item(tr_ui("theme_sakura"), 1)
	_theme_option.set_item_metadata(1, "sakura")
	_theme_option.add_item(tr_ui("theme_onyx"), 2)
	_theme_option.set_item_metadata(2, "onyx")
	_theme_option.add_item(tr_ui("theme_ivory"), 3)
	_theme_option.set_item_metadata(3, "ivory")
	_theme_option.add_item(tr_ui("theme_ember"), 4)
	_theme_option.set_item_metadata(4, "ember")
	_theme_option.add_item(tr_ui("theme_matrix"), 5)
	_theme_option.set_item_metadata(5, "matrix")
	_theme_option.add_item(tr_ui("theme_forest"), 6)
	_theme_option.set_item_metadata(6, "forest")
	_theme_option.add_item(tr_ui("theme_ps2"), 7)
	_theme_option.set_item_metadata(7, "ps2")
	_theme_option.add_item(tr_ui("theme_underground"), 8)
	_theme_option.set_item_metadata(8, "underground")
	_theme_option.add_item(tr_ui("theme_chicago30"), 9)
	_theme_option.set_item_metadata(9, "chicago30")
	_theme_option.add_item(tr_ui("theme_gangster90"), 10)
	_theme_option.set_item_metadata(10, "gangster90")
	_theme_option.add_item(tr_ui("theme_gangsta00"), 11)
	_theme_option.set_item_metadata(11, "gangsta00")
	_theme_option.add_item(tr_ui("theme_teranga"), 12)
	_theme_option.set_item_metadata(12, "teranga")
	_theme_option.add_item(tr_ui("theme_wax"), 13)
	_theme_option.set_item_metadata(13, "wax")
	_theme_option.add_item(tr_ui("theme_sahel"), 14)
	_theme_option.set_item_metadata(14, "sahel")
	_theme_option.add_item(tr_ui("theme_savane"), 15)
	_theme_option.set_item_metadata(15, "savane")
	_theme_option.add_item(tr_ui("theme_synthwave"), 16)
	_theme_option.set_item_metadata(16, "synthwave")
	_theme_option.add_item(tr_ui("theme_cyberpunk"), 17)
	_theme_option.set_item_metadata(17, "cyberpunk")
	_theme_option.add_item(tr_ui("theme_steampunk"), 18)
	_theme_option.set_item_metadata(18, "steampunk")
	_theme_option.add_item(tr_ui("theme_horror"), 19)
	_theme_option.set_item_metadata(19, "horror")
	_theme_option.add_item(tr_ui("theme_minimal"), 20)
	_theme_option.set_item_metadata(20, "minimal")
	_theme_option.add_item(tr_ui("theme_pixel"), 21)
	_theme_option.set_item_metadata(21, "pixel")
	_theme_option.add_item(tr_ui("theme_vaporwave"), 22)
	_theme_option.set_item_metadata(22, "vaporwave")
	_theme_option.add_item(tr_ui("theme_manga"), 23)
	_theme_option.set_item_metadata(23, "manga")
	_theme_option.add_item(tr_ui("theme_ocean"), 24)
	_theme_option.set_item_metadata(24, "ocean")
	_theme_option.add_item(tr_ui("theme_brutalist"), 25)
	_theme_option.set_item_metadata(25, "brutalist")
	_theme_option.add_item(tr_ui("theme_western"), 26)
	_theme_option.set_item_metadata(26, "western")
	_theme_option.add_item(tr_ui("theme_comicbook"), 27)
	_theme_option.set_item_metadata(27, "comicbook")
	_theme_option.add_item(tr_ui("theme_custom"), 28)
	_theme_option.set_item_metadata(28, "custom")
	_theme_option.item_selected.connect(_on_theme_selected)
	_header_tools.add_child(_theme_option)
	_style_option_button(_theme_option)

	_theme_edit_btn = Button.new()
	_theme_edit_btn.text = "🎨"
	_theme_edit_btn.tooltip_text = tr_ui("theme_edit_tip")
	_theme_edit_btn.custom_minimum_size = Vector2(36, 0)
	_theme_edit_btn.pressed.connect(_open_theme_editor)
	_header_tools.add_child(_theme_edit_btn)
	_style_secondary_button(_theme_edit_btn)

	# FX panel (masqué) — CRT / néon / tag / arcade… hors du header pour un look clean
	_fx_toggle_btn = Button.new()
	_fx_toggle_btn.text = tr_ui("fx_panel_btn")
	_fx_toggle_btn.tooltip_text = tr_ui("fx_panel_tip")
	_fx_toggle_btn.custom_minimum_size = Vector2(44, 0)
	_fx_toggle_btn.toggle_mode = true
	_fx_toggle_btn.toggled.connect(_on_fx_panel_toggled)
	_header_tools.add_child(_fx_toggle_btn)
	_style_secondary_button(_fx_toggle_btn)

	_coffee_btn = Button.new()
	_coffee_btn.text = tr_ui("break_btn")
	_coffee_btn.tooltip_text = tr_ui("break_tip")
	_coffee_btn.pressed.connect(_on_coffee_break)
	_header_tools.add_child(_coffee_btn)
	_style_secondary_button(_coffee_btn)

	# --- Panneau FX collapsible (dans le flux, pas overlay) ---
	_fx_panel = PanelContainer.new()
	_fx_panel.visible = false
	_fx_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fx_sb := StyleBoxFlat.new()
	fx_sb.bg_color = Color(C_SURFACE.r, C_SURFACE.g, C_SURFACE.b, 0.92)
	fx_sb.set_corner_radius_all(10)
	fx_sb.content_margin_left = 12
	fx_sb.content_margin_right = 12
	fx_sb.content_margin_top = 10
	fx_sb.content_margin_bottom = 10
	fx_sb.border_width_left = 1
	fx_sb.border_width_right = 1
	fx_sb.border_width_top = 1
	fx_sb.border_width_bottom = 1
	fx_sb.border_color = Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.6)
	_fx_panel.add_theme_stylebox_override("panel", fx_sb)
	header.add_child(_fx_panel)

	var fx_v := VBoxContainer.new()
	fx_v.add_theme_constant_override("separation", 10)
	_fx_panel.add_child(fx_v)

	var fx_title := Label.new()
	fx_title.text = tr_ui("fx_panel_title")
	fx_title.add_theme_font_size_override("font_size", _ed_font(-1))
	fx_title.add_theme_color_override("font_color", C_MUTED)
	fx_v.add_child(fx_title)

	var fx_row1 := HFlowContainer.new()
	fx_row1.add_theme_constant_override("h_separation", 8)
	fx_row1.add_theme_constant_override("v_separation", 8)
	fx_v.add_child(fx_row1)

	_crt_btn = Button.new()
	_crt_btn.text = "CRT"
	_crt_btn.tooltip_text = tr_ui("crt_tip")
	_crt_btn.toggle_mode = true
	_crt_btn.button_pressed = _crt_enabled
	_crt_btn.toggled.connect(_on_crt_toggled)
	fx_row1.add_child(_crt_btn)
	_style_secondary_button(_crt_btn)

	_neon_btn = Button.new()
	_neon_btn.text = "Neon"
	_neon_btn.tooltip_text = tr_ui("neon_tip")
	_neon_btn.toggle_mode = true
	_neon_btn.button_pressed = _neon_enabled
	_neon_btn.toggled.connect(_on_neon_toggled)
	fx_row1.add_child(_neon_btn)
	_style_secondary_button(_neon_btn)

	_predator_btn = Button.new()
	_predator_btn.text = "Predator"
	_predator_btn.tooltip_text = tr_ui("predator_tip")
	_predator_btn.toggle_mode = true
	_predator_btn.button_pressed = _predator_enabled
	_predator_btn.toggled.connect(_on_predator_toggled)
	fx_row1.add_child(_predator_btn)
	_style_secondary_button(_predator_btn)

	_rain_btn = Button.new()
	_rain_btn.text = "Rain"
	_rain_btn.tooltip_text = tr_ui("rain_tip")
	_rain_btn.toggle_mode = true
	_rain_btn.button_pressed = _rain_enabled
	_rain_btn.toggled.connect(_on_rain_toggled)
	fx_row1.add_child(_rain_btn)
	_style_secondary_button(_rain_btn)

	_paper_btn = Button.new()
	_paper_btn.text = "Paper"
	_paper_btn.tooltip_text = tr_ui("paper_tip")
	_paper_btn.toggle_mode = true
	_paper_btn.button_pressed = _paper_enabled
	_paper_btn.toggled.connect(_on_paper_toggled)
	fx_row1.add_child(_paper_btn)
	_style_secondary_button(_paper_btn)

	_arcade_btn = Button.new()
	_arcade_btn.text = "Arcade"
	_arcade_btn.tooltip_text = tr_ui("arcade_tip")
	_arcade_btn.toggle_mode = true
	_arcade_btn.button_pressed = _arcade_copy
	_arcade_btn.toggled.connect(_on_arcade_toggled)
	fx_row1.add_child(_arcade_btn)
	_style_secondary_button(_arcade_btn)

	_sfx_btn = Button.new()
	_sfx_btn.text = "SFX"
	_sfx_btn.tooltip_text = tr_ui("sfx_tip")
	_sfx_btn.toggle_mode = true
	_sfx_btn.button_pressed = _sfx_enabled
	_sfx_btn.toggled.connect(_on_sfx_toggled)
	fx_row1.add_child(_sfx_btn)
	_style_secondary_button(_sfx_btn)

	_tag_btn = Button.new()
	_tag_btn.text = "Tag"
	_tag_btn.tooltip_text = tr_ui("tag_tip")
	_tag_btn.toggle_mode = true
	_tag_btn.button_pressed = _tag_draw_mode
	_tag_btn.toggled.connect(_on_tag_mode_toggled)
	fx_row1.add_child(_tag_btn)
	_style_secondary_button(_tag_btn)

	_chaos_btn = Button.new()
	_chaos_btn.text = tr_ui("chaos_btn")
	_chaos_btn.tooltip_text = tr_ui("chaos_tip")
	_chaos_btn.pressed.connect(_on_chaos_pressed)
	fx_row1.add_child(_chaos_btn)
	_style_secondary_button(_chaos_btn)

	_cozy_btn = Button.new()
	_cozy_btn.text = tr_ui("cozy_btn")
	_cozy_btn.tooltip_text = tr_ui("cozy_tip")
	_cozy_btn.toggle_mode = true
	_cozy_btn.button_pressed = _cozy_mode
	_cozy_btn.toggled.connect(_on_cozy_toggled)
	fx_row1.add_child(_cozy_btn)
	_style_secondary_button(_cozy_btn)

	# Intensités — visibles seulement si l’effet est actif
	var fx_row2 := VBoxContainer.new()
	fx_row2.add_theme_constant_override("separation", 6)
	fx_v.add_child(fx_row2)
	fx_row2.name = "FxIntensityRows"

	var crt_row := HBoxContainer.new()
	crt_row.name = "CrtIntensityRow"
	crt_row.visible = _crt_enabled
	crt_row.add_theme_constant_override("separation", 8)
	fx_row2.add_child(crt_row)
	var crt_lbl := Label.new()
	crt_lbl.text = tr_ui("crt_intensity")
	crt_lbl.custom_minimum_size = Vector2(48, 0)
	crt_lbl.add_theme_font_size_override("font_size", _ed_font(-2))
	crt_row.add_child(crt_lbl)
	_crt_intensity_slider = HSlider.new()
	_crt_intensity_slider.min_value = 0.05
	_crt_intensity_slider.max_value = 1.0
	_crt_intensity_slider.step = 0.05
	_crt_intensity_slider.value = _crt_intensity
	_crt_intensity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crt_intensity_slider.value_changed.connect(_on_crt_intensity_changed)
	crt_row.add_child(_crt_intensity_slider)
	var crt_pct := Label.new()
	crt_pct.name = "CrtPct"
	crt_pct.text = "%d%%" % int(_crt_intensity * 100.0)
	crt_pct.custom_minimum_size = Vector2(40, 0)
	crt_pct.add_theme_font_size_override("font_size", _ed_font(-2))
	crt_row.add_child(crt_pct)

	var neon_row := HBoxContainer.new()
	neon_row.name = "NeonIntensityRow"
	neon_row.visible = _neon_enabled
	neon_row.add_theme_constant_override("separation", 8)
	fx_row2.add_child(neon_row)
	var neon_lbl := Label.new()
	neon_lbl.text = tr_ui("neon_intensity")
	neon_lbl.custom_minimum_size = Vector2(48, 0)
	neon_lbl.add_theme_font_size_override("font_size", _ed_font(-2))
	neon_row.add_child(neon_lbl)
	_neon_slider = HSlider.new()
	_neon_slider.min_value = 0.15
	_neon_slider.max_value = 1.4
	_neon_slider.step = 0.05
	_neon_slider.value = _neon_intensity
	_neon_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_neon_slider.value_changed.connect(_on_neon_intensity_changed)
	neon_row.add_child(_neon_slider)
	var neon_pct := Label.new()
	neon_pct.name = "NeonPct"
	neon_pct.text = "%d%%" % int(_neon_intensity * 100.0)
	neon_pct.custom_minimum_size = Vector2(40, 0)
	neon_pct.add_theme_font_size_override("font_size", _ed_font(-2))
	neon_row.add_child(neon_pct)

	var pred_row := HBoxContainer.new()
	pred_row.name = "PredatorIntensityRow"
	pred_row.visible = _predator_enabled
	pred_row.add_theme_constant_override("separation", 8)
	fx_row2.add_child(pred_row)
	var pred_lbl := Label.new()
	pred_lbl.text = tr_ui("predator_intensity")
	pred_lbl.custom_minimum_size = Vector2(56, 0)
	pred_lbl.add_theme_font_size_override("font_size", _ed_font(-2))
	pred_row.add_child(pred_lbl)
	var pred_slider := HSlider.new()
	pred_slider.name = "PredatorSlider"
	pred_slider.min_value = 0.1
	pred_slider.max_value = 1.0
	pred_slider.step = 0.05
	pred_slider.value = _predator_intensity
	pred_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pred_slider.value_changed.connect(_on_predator_intensity_changed)
	pred_row.add_child(pred_slider)
	var pred_pct := Label.new()
	pred_pct.name = "PredatorPct"
	pred_pct.text = "%d%%" % int(_predator_intensity * 100.0)
	pred_pct.custom_minimum_size = Vector2(40, 0)
	pred_pct.add_theme_font_size_override("font_size", _ed_font(-2))
	pred_row.add_child(pred_pct)

	var rain_row := HBoxContainer.new()
	rain_row.name = "RainIntensityRow"
	rain_row.visible = _rain_enabled
	rain_row.add_theme_constant_override("separation", 8)
	fx_row2.add_child(rain_row)
	var rain_lbl := Label.new()
	rain_lbl.text = tr_ui("rain_intensity")
	rain_lbl.custom_minimum_size = Vector2(56, 0)
	rain_lbl.add_theme_font_size_override("font_size", _ed_font(-2))
	rain_row.add_child(rain_lbl)
	var rain_slider := HSlider.new()
	rain_slider.name = "RainSlider"
	rain_slider.min_value = 0.1
	rain_slider.max_value = 1.0
	rain_slider.step = 0.05
	rain_slider.value = _rain_intensity
	rain_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rain_slider.value_changed.connect(_on_rain_intensity_changed)
	rain_row.add_child(rain_slider)
	var rain_pct := Label.new()
	rain_pct.name = "RainPct"
	rain_pct.text = "%d%%" % int(_rain_intensity * 100.0)
	rain_pct.custom_minimum_size = Vector2(40, 0)
	rain_pct.add_theme_font_size_override("font_size", _ed_font(-2))
	rain_row.add_child(rain_pct)

	var paper_row := HBoxContainer.new()
	paper_row.name = "PaperIntensityRow"
	paper_row.visible = _paper_enabled
	paper_row.add_theme_constant_override("separation", 8)
	fx_row2.add_child(paper_row)
	var paper_lbl := Label.new()
	paper_lbl.text = tr_ui("paper_intensity")
	paper_lbl.custom_minimum_size = Vector2(56, 0)
	paper_lbl.add_theme_font_size_override("font_size", _ed_font(-2))
	paper_row.add_child(paper_lbl)
	var paper_slider := HSlider.new()
	paper_slider.name = "PaperSlider"
	paper_slider.min_value = 0.1
	paper_slider.max_value = 1.0
	paper_slider.step = 0.05
	paper_slider.value = _paper_intensity
	paper_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paper_slider.value_changed.connect(_on_paper_intensity_changed)
	paper_row.add_child(paper_slider)
	var paper_pct := Label.new()
	paper_pct.name = "PaperPct"
	paper_pct.text = "%d%%" % int(_paper_intensity * 100.0)
	paper_pct.custom_minimum_size = Vector2(40, 0)
	paper_pct.add_theme_font_size_override("font_size", _ed_font(-2))
	paper_row.add_child(paper_pct)

	# Mini play dans le header (contrôle rapide)
	_music_play_btn = Button.new()
	_music_play_btn.text = tr_ui("music_play")
	_music_play_btn.tooltip_text = tr_ui("music_tip")
	_music_play_btn.custom_minimum_size = Vector2(36, 0)
	_music_play_btn.pressed.connect(_on_music_toggle)
	_header_tools.add_child(_music_play_btn)
	_style_secondary_button(_music_play_btn)

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "CodingMusic"
	_music_player.bus = "Master"
	_music_player.volume_db = _music_volume_db
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)

	if Engine.is_editor_hint():
		_music_file_dialog = EditorFileDialog.new()
		_music_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILES
		_music_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_music_file_dialog.title = tr_ui("music_tip")
		_music_file_dialog.add_filter("*.ogg, *.mp3, *.wav, *.flac", "Audio")
		_music_file_dialog.files_selected.connect(_on_music_files_selected)
		_music_file_dialog.file_selected.connect(_on_music_file_selected)  # fallback 1 fichier
		add_child(_music_file_dialog)

	# Indicateur de connexion (pastille + texte)
	var conn_row := HBoxContainer.new()
	conn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	conn_row.add_theme_constant_override("separation", 8)
	conn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(conn_row)

	_conn_dot = Panel.new()
	_conn_dot.custom_minimum_size = Vector2(10, 10)
	_conn_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_set_conn_dot_color(C_ERR)
	conn_row.add_child(_conn_dot)

	_conn_label = Label.new()
	_conn_label.text = tr_ui("not_connected")
	_conn_label.modulate = C_MUTED
	_conn_label.add_theme_font_size_override("font_size", _ed_font())
	conn_row.add_child(_conn_label)

	user_label = Label.new()
	user_label.visible = false
	user_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	user_label.modulate = C_OK
	user_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	user_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	user_label.add_theme_font_size_override("font_size", _ed_font())
	header.add_child(user_label)

	# Bannière de feedback (toujours visible)
	_status_banner = PanelContainer.new()
	_status_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var banner_sb := StyleBoxFlat.new()
	banner_sb.bg_color = C_BANNER_IDLE
	banner_sb.set_corner_radius_all(10)
	banner_sb.content_margin_left = 12
	banner_sb.content_margin_right = 12
	banner_sb.content_margin_top = 10
	banner_sb.content_margin_bottom = 10
	banner_sb.border_width_left = 1
	banner_sb.border_width_right = 1
	banner_sb.border_width_top = 1
	banner_sb.border_width_bottom = 1
	banner_sb.border_color = C_BORDER
	_status_banner.add_theme_stylebox_override("panel", banner_sb)
	header.add_child(_status_banner)

	_status_banner_label = Label.new()
	_status_banner_label.text = tr_ui("login_to_start")
	_status_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_banner_label.add_theme_font_size_override("font_size", _ed_font())
	_status_banner.add_child(_status_banner_label)

	# ── Onboarding (première session) ───────────────────────────────────────
	_onboarding_panel = PanelContainer.new()
	_onboarding_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ob_sb := StyleBoxFlat.new()
	ob_sb.bg_color = Color(C_CARD.r, C_CARD.g, C_CARD.b, 0.98)
	ob_sb.set_corner_radius_all(12)
	ob_sb.content_margin_left = 14
	ob_sb.content_margin_right = 14
	ob_sb.content_margin_top = 12
	ob_sb.content_margin_bottom = 12
	ob_sb.border_width_left = 1
	ob_sb.border_width_right = 1
	ob_sb.border_width_top = 1
	ob_sb.border_width_bottom = 1
	ob_sb.border_color = C_PRIMARY
	ob_sb.shadow_color = Color(0, 0, 0, 0.2)
	ob_sb.shadow_size = 4
	ob_sb.shadow_offset = Vector2(0, 2)
	_onboarding_panel.add_theme_stylebox_override("panel", ob_sb)
	header.add_child(_onboarding_panel)

	var ob_col := VBoxContainer.new()
	ob_col.add_theme_constant_override("separation", 8)
	_onboarding_panel.add_child(ob_col)

	_onboarding_title = Label.new()
	_onboarding_title.text = tr_ui("ob_title")
	_onboarding_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_onboarding_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_onboarding_title.add_theme_font_size_override("font_size", _ed_font(1))
	_onboarding_title.add_theme_color_override("font_color", C_PRIMARY)
	ob_col.add_child(_onboarding_title)

	_onboarding_next = Label.new()
	_onboarding_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_onboarding_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_onboarding_next.add_theme_font_size_override("font_size", _ed_font())
	_onboarding_next.modulate = C_TEXT
	ob_col.add_child(_onboarding_next)

	_onboarding_steps_box = VBoxContainer.new()
	_onboarding_steps_box.add_theme_constant_override("separation", 4)
	ob_col.add_child(_onboarding_steps_box)

	_onboarding_step_btns.clear()
	for i in range(5):
		var sb := Button.new()
		sb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.pressed.connect(_on_onboarding_step_pressed.bind(i))
		_style_secondary_button(sb)
		_onboarding_steps_box.add_child(sb)
		_onboarding_step_btns.append(sb)

	var ob_actions := HBoxContainer.new()
	ob_actions.add_theme_constant_override("separation", 8)
	ob_col.add_child(ob_actions)

	_onboarding_skip_btn = Button.new()
	_onboarding_skip_btn.text = tr_ui("ob_skip")
	_onboarding_skip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_onboarding_skip_btn.pressed.connect(_on_onboarding_skip)
	ob_actions.add_child(_onboarding_skip_btn)
	_style_secondary_button(_onboarding_skip_btn)

	_onboarding_dismiss_btn = Button.new()
	_onboarding_dismiss_btn.text = tr_ui("ob_dismiss")
	_onboarding_dismiss_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_onboarding_dismiss_btn.pressed.connect(_on_onboarding_skip)
	_onboarding_dismiss_btn.visible = false
	ob_actions.add_child(_onboarding_dismiss_btn)
	_style_primary_button(_onboarding_dismiss_btn)

	# Accueil + conseil du moment (confort)
	_greet_label = Label.new()
	_greet_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_greet_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_greet_label.add_theme_font_size_override("font_size", _ed_font(-1))
	_greet_label.modulate = C_MUTED
	header.add_child(_greet_label)

	_tip_label = Label.new()
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip_label.add_theme_font_size_override("font_size", _ed_font(-1))
	_tip_label.modulate = C_MUTED
	header.add_child(_tip_label)

	_festive_banner = Label.new()
	_festive_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_festive_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_festive_banner.add_theme_font_size_override("font_size", _ed_font())
	_festive_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_festive_banner.visible = false
	header.add_child(_festive_banner)

	_garland_bar = HBoxContainer.new()
	_garland_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_garland_bar.add_theme_constant_override("separation", 4)
	_garland_bar.visible = false
	header.add_child(_garland_bar)

	_tip_timer = Timer.new()
	_tip_timer.wait_time = 12.0
	_tip_timer.timeout.connect(_on_comfort_tip_tick)
	add_child(_tip_timer)
	_tip_timer.start()

	# Recalcule l’ambiance festive si le jour change (éditeur resté ouvert)
	var festive_day_timer := Timer.new()
	festive_day_timer.wait_time = 3600.0  # 1 h
	festive_day_timer.timeout.connect(func():
		_festive_apply()
		_night_focus_apply()
	)
	add_child(festive_day_timer)
	festive_day_timer.start()

	_busy_tip_timer = Timer.new()
	_busy_tip_timer.wait_time = 7.0
	_busy_tip_timer.timeout.connect(_on_busy_tip_tick)
	add_child(_busy_tip_timer)

	_feedback_timer = Timer.new()
	_feedback_timer.one_shot = true
	_feedback_timer.wait_time = 6.0
	_feedback_timer.timeout.connect(_on_feedback_timeout)
	add_child(_feedback_timer)

	# ── 1. CONNEXION ────────────────────────────────────────────────────────
	# ── LECTEUR AUDIO AVANCÉ ────────────────────────────────────────────────
	_sec_music = _make_section_card(tr_ui("music_sec"), false)
	root.add_child(_sec_music)
	var music_body := _section_body(_sec_music)

	_music_label = Label.new()
	_music_label.text = tr_ui("music_none")
	_music_label.modulate = C_MUTED
	_music_label.add_theme_font_size_override("font_size", _ed_font())
	_music_label.clip_text = true
	_music_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_body.add_child(_music_label)

	_music_seek = HSlider.new()
	_music_seek.min_value = 0.0
	_music_seek.max_value = 1.0
	_music_seek.step = 0.001
	_music_seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_seek.tooltip_text = tr_ui("music_seek")
	_music_seek.drag_started.connect(func(): _music_seeking = true)
	_music_seek.drag_ended.connect(_on_music_seek_ended)
	music_body.add_child(_music_seek)

	_music_time_label = Label.new()
	_music_time_label.text = tr_ui("music_time") % ["0:00", "0:00"]
	_music_time_label.modulate = C_MUTED
	_music_time_label.add_theme_font_size_override("font_size", _ed_font(-1))
	_music_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	music_body.add_child(_music_time_label)

	var music_ctrl := HBoxContainer.new()
	music_ctrl.add_theme_constant_override("separation", 8)
	music_ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_body.add_child(music_ctrl)

	_music_pick_btn = Button.new()
	_music_pick_btn.text = tr_ui("music_pick")
	_music_pick_btn.tooltip_text = tr_ui("music_tip")
	_music_pick_btn.pressed.connect(_on_music_pick)
	music_ctrl.add_child(_music_pick_btn)
	_style_secondary_button(_music_pick_btn)

	# play/pause already in header; duplicate control here for full player
	var play2 := Button.new()
	play2.text = tr_ui("music_play")
	play2.custom_minimum_size = Vector2(44, 0)
	play2.pressed.connect(_on_music_toggle)
	play2.set_meta("music_play_mirror", true)
	music_ctrl.add_child(play2)
	_style_primary_button(play2)
	# Keep reference via group-like: store as second play if needed — update both in _music_sync_ui
	if not has_meta("music_play2"):
		set_meta("music_play2", play2)

	_music_stop_btn = Button.new()
	_music_stop_btn.text = tr_ui("music_stop")
	_music_stop_btn.custom_minimum_size = Vector2(44, 0)
	_music_stop_btn.pressed.connect(_on_music_stop)
	music_ctrl.add_child(_music_stop_btn)
	_style_secondary_button(_music_stop_btn)

	_music_loop_check = CheckBox.new()
	_music_loop_check.text = tr_ui("music_loop")
	_music_loop_check.button_pressed = _music_loop
	_music_loop_check.toggled.connect(_on_music_loop_toggled)
	music_ctrl.add_child(_music_loop_check)
	_style_checkbox(_music_loop_check)

	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 8)
	vol_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_body.add_child(vol_row)

	var vol_l := Label.new()
	vol_l.text = tr_ui("music_vol")
	vol_l.modulate = C_MUTED
	vol_l.add_theme_font_size_override("font_size", _ed_font(-1))
	vol_row.add_child(vol_l)

	_music_vol = HSlider.new()
	_music_vol.min_value = -40.0
	_music_vol.max_value = 0.0
	_music_vol.step = 0.5
	_music_vol.value = _music_volume_db
	_music_vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_vol.value_changed.connect(_on_music_volume_changed)
	vol_row.add_child(_music_vol)

	_music_mute_check = CheckBox.new()
	_music_mute_check.text = tr_ui("music_mute")
	_music_mute_check.toggled.connect(_on_music_mute_toggled)
	vol_row.add_child(_music_mute_check)
	_style_checkbox(_music_mute_check)

	var rate_row := HBoxContainer.new()
	rate_row.add_theme_constant_override("separation", 8)
	music_body.add_child(rate_row)

	var rate_l := Label.new()
	rate_l.text = tr_ui("music_rate")
	rate_l.modulate = C_MUTED
	rate_l.add_theme_font_size_override("font_size", _ed_font(-1))
	rate_row.add_child(rate_l)

	_music_rate = OptionButton.new()
	_music_rate.add_item("0.75×", 0)
	_music_rate.set_item_metadata(0, 0.75)
	_music_rate.add_item("1×", 1)
	_music_rate.set_item_metadata(1, 1.0)
	_music_rate.add_item("1.25×", 2)
	_music_rate.set_item_metadata(2, 1.25)
	_music_rate.add_item("1.5×", 3)
	_music_rate.set_item_metadata(3, 1.5)
	_music_rate.select(1)
	_music_rate.item_selected.connect(_on_music_rate_selected)
	rate_row.add_child(_music_rate)
	_style_option_button(_music_rate)

	# ── Playlist ────────────────────────────────────────────────────────────
	_music_pl_label = Label.new()
	_music_pl_label.text = tr_ui("music_playlist")
	_music_pl_label.modulate = C_MUTED
	_music_pl_label.add_theme_font_size_override("font_size", _ed_font(-1))
	music_body.add_child(_music_pl_label)

	_music_playlist_list = ItemList.new()
	_music_playlist_list.custom_minimum_size = Vector2(0, 110)
	_music_playlist_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_playlist_list.select_mode = ItemList.SELECT_SINGLE
	_music_playlist_list.allow_reselect = true
	_music_playlist_list.item_activated.connect(_on_music_playlist_activated)
	_music_playlist_list.item_selected.connect(_on_music_playlist_selected)
	music_body.add_child(_music_playlist_list)

	var pl_btns := HBoxContainer.new()
	pl_btns.add_theme_constant_override("separation", 6)
	pl_btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_body.add_child(pl_btns)

	_music_add_btn = Button.new()
	_music_add_btn.text = tr_ui("music_pl_add")
	_music_add_btn.tooltip_text = tr_ui("music_pl_add_tip")
	_music_add_btn.pressed.connect(_on_music_pick)
	pl_btns.add_child(_music_add_btn)
	_style_secondary_button(_music_add_btn)

	_music_remove_btn = Button.new()
	_music_remove_btn.text = tr_ui("music_pl_remove")
	_music_remove_btn.tooltip_text = tr_ui("music_pl_remove_tip")
	_music_remove_btn.pressed.connect(_on_music_playlist_remove)
	pl_btns.add_child(_music_remove_btn)
	_style_secondary_button(_music_remove_btn)

	_music_clear_pl_btn = Button.new()
	_music_clear_pl_btn.text = tr_ui("music_pl_clear")
	_music_clear_pl_btn.tooltip_text = tr_ui("music_pl_clear_tip")
	_music_clear_pl_btn.pressed.connect(_on_music_playlist_clear)
	pl_btns.add_child(_music_clear_pl_btn)
	_style_secondary_button(_music_clear_pl_btn)

	_music_prev_btn = Button.new()
	_music_prev_btn.text = tr_ui("music_prev")
	_music_prev_btn.custom_minimum_size = Vector2(40, 0)
	_music_prev_btn.tooltip_text = tr_ui("music_prev_tip")
	_music_prev_btn.pressed.connect(_on_music_prev)
	pl_btns.add_child(_music_prev_btn)
	_style_secondary_button(_music_prev_btn)

	_music_next_btn = Button.new()
	_music_next_btn.text = tr_ui("music_next")
	_music_next_btn.custom_minimum_size = Vector2(40, 0)
	_music_next_btn.tooltip_text = tr_ui("music_next_tip")
	_music_next_btn.pressed.connect(_on_music_next)
	pl_btns.add_child(_music_next_btn)
	_style_secondary_button(_music_next_btn)

	# ── LECTEUR VIDÉO (section Avancé) ──────────────────────────────────────
	_sec_video = _make_section_card(tr_ui("video_sec"), false)
	root.add_child(_sec_video)
	var video_body := _section_body(_sec_video)

	_video_hint = Label.new()
	_video_hint.text = tr_ui("video_hint")
	_video_hint.modulate = C_MUTED
	_video_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_video_hint.add_theme_font_size_override("font_size", _ed_font(-1))
	_video_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	video_body.add_child(_video_hint)

	_video_label = Label.new()
	_video_label.text = tr_ui("video_none")
	_video_label.modulate = C_MUTED
	_video_label.clip_text = true
	_video_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_video_label.add_theme_font_size_override("font_size", _ed_font())
	video_body.add_child(_video_label)

	# Conteneur pour la vidéo (ratio 16:9 approximatif dans le dock)
	var video_frame := PanelContainer.new()
	video_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	video_frame.custom_minimum_size = Vector2(0, 180)
	var vf_style := StyleBoxFlat.new()
	vf_style.bg_color = Color(0.06, 0.07, 0.09, 1.0)
	vf_style.set_corner_radius_all(8)
	vf_style.content_margin_left = 2
	vf_style.content_margin_right = 2
	vf_style.content_margin_top = 2
	vf_style.content_margin_bottom = 2
	video_frame.add_theme_stylebox_override("panel", vf_style)
	video_body.add_child(video_frame)

	_video_player = VideoStreamPlayer.new()
	_video_player.name = "WellbeingVideo"
	_video_player.expand = true
	_video_player.buffering_msec = 500
	_video_player.custom_minimum_size = Vector2(0, 176)
	_video_player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_video_player.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_video_player.finished.connect(_on_video_finished)
	video_frame.add_child(_video_player)

	_video_seek = HSlider.new()
	_video_seek.min_value = 0.0
	_video_seek.max_value = 1.0
	_video_seek.step = 0.001
	_video_seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_video_seek.tooltip_text = tr_ui("video_seek")
	_video_seek.drag_started.connect(func(): _video_seeking = true)
	_video_seek.drag_ended.connect(_on_video_seek_ended)
	video_body.add_child(_video_seek)

	_video_time_label = Label.new()
	_video_time_label.text = tr_ui("video_time") % ["0:00", "0:00"]
	_video_time_label.modulate = C_MUTED
	_video_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_video_time_label.add_theme_font_size_override("font_size", _ed_font(-1))
	video_body.add_child(_video_time_label)

	var video_ctrl := HBoxContainer.new()
	video_ctrl.add_theme_constant_override("separation", 8)
	video_ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	video_body.add_child(video_ctrl)

	_video_pick_btn = Button.new()
	_video_pick_btn.text = tr_ui("video_pick")
	_video_pick_btn.tooltip_text = tr_ui("video_tip")
	_video_pick_btn.pressed.connect(_on_video_pick)
	video_ctrl.add_child(_video_pick_btn)
	_style_secondary_button(_video_pick_btn)

	_video_play_btn = Button.new()
	_video_play_btn.text = tr_ui("video_play")
	_video_play_btn.custom_minimum_size = Vector2(44, 0)
	_video_play_btn.pressed.connect(_on_video_toggle)
	video_ctrl.add_child(_video_play_btn)
	_style_primary_button(_video_play_btn)

	_video_stop_btn = Button.new()
	_video_stop_btn.text = tr_ui("video_stop")
	_video_stop_btn.custom_minimum_size = Vector2(44, 0)
	_video_stop_btn.pressed.connect(_on_video_stop)
	video_ctrl.add_child(_video_stop_btn)
	_style_secondary_button(_video_stop_btn)

	_video_loop_check = CheckBox.new()
	_video_loop_check.text = tr_ui("video_loop")
	_video_loop_check.button_pressed = _video_loop
	_video_loop_check.toggled.connect(_on_video_loop_toggled)
	video_ctrl.add_child(_video_loop_check)
	_style_checkbox(_video_loop_check)

	var video_vol_row := HBoxContainer.new()
	video_vol_row.add_theme_constant_override("separation", 8)
	video_vol_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	video_body.add_child(video_vol_row)

	var video_vol_l := Label.new()
	video_vol_l.text = tr_ui("video_vol")
	video_vol_l.modulate = C_MUTED
	video_vol_l.add_theme_font_size_override("font_size", _ed_font(-1))
	video_vol_row.add_child(video_vol_l)

	_video_vol = HSlider.new()
	_video_vol.min_value = 0.0
	_video_vol.max_value = 1.0
	_video_vol.step = 0.05
	_video_vol.value = _video_volume
	_video_vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_video_vol.value_changed.connect(_on_video_volume_changed)
	video_vol_row.add_child(_video_vol)

	_video_open_os_btn = Button.new()
	_video_open_os_btn.text = tr_ui("video_open_os")
	_video_open_os_btn.tooltip_text = tr_ui("video_open_os_tip")
	_video_open_os_btn.pressed.connect(_on_video_open_os)
	video_vol_row.add_child(_video_open_os_btn)
	_style_secondary_button(_video_open_os_btn)

	if Engine.is_editor_hint():
		_video_file_dialog = EditorFileDialog.new()
		_video_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_video_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_video_file_dialog.title = tr_ui("video_open")
		_video_file_dialog.add_filter("*.ogv", "Ogg Theora (Godot)")
		_video_file_dialog.add_filter("*.ogv, *.ogg", "Ogg video")
		_video_file_dialog.add_filter("*.mp4, *.webm, *.mkv, *.avi, *.mov", "Other video (OS player)")
		_video_file_dialog.file_selected.connect(_on_video_file_selected)
		add_child(_video_file_dialog)

	_sec_conn = _make_section_card(tr_ui("sec_conn"), true)
	root.add_child(_sec_conn)
	var conn_body := _section_body(_sec_conn)

	api_base_edit = LineEdit.new()
	api_base_edit.placeholder_text = tr_ui("api_ph")
	api_base_edit.text = "https://api.thiossane.store/api"
	api_base_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conn_body.add_child(api_base_edit)
	_style_line_edit(api_base_edit)

	_row_auth = HBoxContainer.new()
	_row_auth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_auth.add_theme_constant_override("separation", 10)
	conn_body.add_child(_row_auth)

	email_edit = LineEdit.new()
	email_edit.placeholder_text = tr_ui("email_ph")
	email_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_auth.add_child(email_edit)
	_style_line_edit(email_edit)

	password_edit = LineEdit.new()
	password_edit.placeholder_text = tr_ui("password_ph")
	password_edit.secret = true
	password_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_auth.add_child(password_edit)
	_style_line_edit(password_edit)

	var auth_btns_row := HBoxContainer.new()
	auth_btns_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auth_btns_row.add_theme_constant_override("separation", 12)
	conn_body.add_child(auth_btns_row)

	connect_btn = Button.new()
	connect_btn.text = tr_ui("connect")
	connect_btn.tooltip_text = tr_ui("connect_tip")
	connect_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connect_btn.size_flags_stretch_ratio = 1.4
	connect_btn.pressed.connect(_on_connect_pressed)
	auth_btns_row.add_child(connect_btn)
	_style_primary_button(connect_btn)

	var logout_btn := Button.new()
	logout_btn.text = tr_ui("logout")
	logout_btn.tooltip_text = tr_ui("logout_tip")
	logout_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logout_btn.size_flags_stretch_ratio = 1.0
	logout_btn.pressed.connect(_on_logout_pressed)
	auth_btns_row.add_child(logout_btn)
	_style_secondary_button(logout_btn)
	_logout_btn = logout_btn

	var auth_fb := _make_local_feedback()
	_fb_auth = auth_fb[0]
	_fb_auth_label = auth_fb[1]
	conn_body.add_child(_fb_auth)

	# ── 2. SÉLECTION DU JEU ─────────────────────────────────────────────────
	_sec_game = _make_section_card(tr_ui("sec_game"), true)
	root.add_child(_sec_game)
	var game_body := _section_body(_sec_game)

	var game_sel_row := HBoxContainer.new()
	game_sel_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_sel_row.add_theme_constant_override("separation", 10)
	game_body.add_child(game_sel_row)

	game_option = OptionButton.new()
	game_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_option.tooltip_text = tr_ui("game_tip")
	game_option.item_selected.connect(_on_game_selected)
	game_sel_row.add_child(game_option)
	_game_empty_label = Label.new()
	_game_empty_label.text = tr_ui("ob_game_empty")
	_game_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_game_empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_empty_label.add_theme_font_size_override("font_size", _ed_font())
	_game_empty_label.modulate = C_MUTED
	_game_empty_label.visible = false
	game_body.add_child(_game_empty_label)
	_style_option_button(game_option)

	refresh_games_btn = Button.new()
	refresh_games_btn.text = tr_ui("refresh_games")
	refresh_games_btn.tooltip_text = tr_ui("refresh_games_tip")
	refresh_games_btn.pressed.connect(_on_refresh_games)
	game_sel_row.add_child(refresh_games_btn)
	_style_secondary_button(refresh_games_btn)

	game_status_label = Label.new()
	game_status_label.text = tr_ui("status_new")
	game_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_status_label.add_theme_font_size_override("font_size", _ed_font())
	game_status_label.modulate = C_MUTED
	game_body.add_child(game_status_label)

	# ── 3. FICHE (détails) ──────────────────────────────────────────────────
	_sec_fiche = _make_section_card(tr_ui("sec_fiche"), true)
	root.add_child(_sec_fiche)
	var fiche_body := _section_body(_sec_fiche)

	_row_title_ver = HBoxContainer.new()
	_row_title_ver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_title_ver.add_theme_constant_override("separation", 10)
	fiche_body.add_child(_row_title_ver)

	title_edit = LineEdit.new()
	title_edit.placeholder_text = tr_ui("title_ph")
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_edit.size_flags_stretch_ratio = 2.5
	_row_title_ver.add_child(title_edit)
	_style_line_edit(title_edit)

	version_edit = LineEdit.new()
	version_edit.placeholder_text = tr_ui("version_ph")
	version_edit.text = "1.0.0"
	version_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	version_edit.size_flags_stretch_ratio = 1.0
	version_edit.tooltip_text = tr_ui("version_tip")
	_row_title_ver.add_child(version_edit)
	_style_line_edit(version_edit)

	desc_edit = TextEdit.new()
	desc_edit.placeholder_text = tr_ui("desc_ph")
	desc_edit.custom_minimum_size.y = 72
	desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fiche_body.add_child(desc_edit)
	_style_text_edit(desc_edit)

	_row_cat_price = HBoxContainer.new()
	_row_cat_price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_cat_price.add_theme_constant_override("separation", 12)
	fiche_body.add_child(_row_cat_price)

	var cat_wrap := VBoxContainer.new()
	cat_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cat_wrap.size_flags_stretch_ratio = 1.5
	cat_wrap.add_theme_constant_override("separation", 4)
	_row_cat_price.add_child(cat_wrap)
	var cat_label := Label.new()
	cat_label.text = tr_ui("category")
	_cat_label = cat_label
	cat_label.add_theme_font_size_override("font_size", _ed_font())
	cat_label.add_theme_color_override("font_color", C_MUTED)
	cat_wrap.add_child(cat_label)
	category_option = OptionButton.new()
	category_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cat_wrap.add_child(category_option)
	_style_option_button(category_option)

	var price_wrap := VBoxContainer.new()
	price_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_wrap.size_flags_stretch_ratio = 1.0
	price_wrap.add_theme_constant_override("separation", 4)
	_row_cat_price.add_child(price_wrap)
	var price_label := Label.new()
	price_label.text = tr_ui("price")
	_price_label = price_label
	price_label.add_theme_font_size_override("font_size", _ed_font())
	price_label.add_theme_color_override("font_color", C_MUTED)
	price_wrap.add_child(price_label)
	price_edit = SpinBox.new()
	price_edit.min_value = 0
	price_edit.max_value = 1_000_000
	price_edit.step = 100
	price_edit.value = 0
	price_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_wrap.add_child(price_edit)
	_style_spinbox(price_edit)

	_row_checks = HBoxContainer.new()
	_row_checks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_checks.add_theme_constant_override("separation", 14)
	fiche_body.add_child(_row_checks)

	free_check = CheckBox.new()
	free_check.text = tr_ui("free")
	free_check.toggled.connect(func(on: bool): price_edit.editable = not on)
	_row_checks.add_child(free_check)
	_style_checkbox(free_check)

	demo_check = CheckBox.new()
	demo_check.text = tr_ui("demo")
	_row_checks.add_child(demo_check)
	_style_checkbox(demo_check)

	browser_check = CheckBox.new()
	browser_check.text = tr_ui("browser")
	browser_check.tooltip_text = tr_ui("browser_tip")
	_row_checks.add_child(browser_check)
	_style_checkbox(browser_check)

	var opt_label := Label.new()
	opt_label.text = tr_ui("optional")
	_opt_label = opt_label
	opt_label.add_theme_font_size_override("font_size", _ed_font(-1))
	opt_label.add_theme_color_override("font_color", C_MUTED)
	fiche_body.add_child(opt_label)

	release_edit = LineEdit.new()
	release_edit.placeholder_text = tr_ui("release_ph")
	release_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fiche_body.add_child(release_edit)
	_style_line_edit(release_edit)

	cover_edit = LineEdit.new()
	cover_edit.placeholder_text = tr_ui("cover_ph")
	cover_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fiche_body.add_child(cover_edit)
	_style_line_edit(cover_edit)

	create_game_btn = Button.new()
	create_game_btn.text = tr_ui("save_fiche")
	create_game_btn.tooltip_text = tr_ui("save_fiche_tip")
	create_game_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_game_btn.pressed.connect(_on_create_game_pressed)
	fiche_body.add_child(create_game_btn)
	_style_primary_button(create_game_btn)

	var fiche_fb := _make_local_feedback()
	_fb_fiche = fiche_fb[0]
	_fb_fiche_label = fiche_fb[1]
	fiche_body.add_child(_fb_fiche)

	# ── 4. PLATEFORMES ──────────────────────────────────────────────────────
	_sec_plat = _make_section_card(tr_ui("sec_plat"), true)
	root.add_child(_sec_plat)
	var plat_body := _section_body(_sec_plat)

	_plat_grid = VBoxContainer.new()
	_plat_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plat_grid.add_theme_constant_override("separation", 8)
	plat_body.add_child(_plat_grid)

	var web_row := _plat_row_container()
	_plat_grid.add_child(web_row)
	platform_web = CheckBox.new()
	platform_web.text = "Web"
	platform_web.button_pressed = true
	platform_web.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	web_row.add_child(platform_web)
	_style_checkbox(platform_web)
	preset_web = OptionButton.new()
	preset_web.tooltip_text = tr_ui("preset_web_tip")
	preset_web.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_web.size_flags_stretch_ratio = 1.6
	web_row.add_child(preset_web)
	_style_option_button(preset_web)

	var win_row := _plat_row_container()
	_plat_grid.add_child(win_row)
	platform_windows = CheckBox.new()
	platform_windows.text = "Windows"
	platform_windows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	win_row.add_child(platform_windows)
	_style_checkbox(platform_windows)
	preset_windows = OptionButton.new()
	preset_windows.tooltip_text = tr_ui("preset_win_tip")
	preset_windows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_windows.size_flags_stretch_ratio = 1.6
	win_row.add_child(preset_windows)
	_style_option_button(preset_windows)

	var and_row := _plat_row_container()
	_plat_grid.add_child(and_row)
	platform_android = CheckBox.new()
	platform_android.text = "Android"
	platform_android.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	and_row.add_child(platform_android)
	_style_checkbox(platform_android)
	preset_android = OptionButton.new()
	preset_android.tooltip_text = tr_ui("preset_and_tip")
	preset_android.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_android.size_flags_stretch_ratio = 1.6
	and_row.add_child(preset_android)
	_style_option_button(preset_android)

	var refresh_presets_btn := Button.new()
	refresh_presets_btn.text = tr_ui("refresh_presets")
	_refresh_presets_btn = refresh_presets_btn
	refresh_presets_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_presets_btn.pressed.connect(_refresh_presets)
	plat_body.add_child(refresh_presets_btn)
	_style_secondary_button(refresh_presets_btn)

	# ── 5. DÉPLOIEMENT (action principale) ──────────────────────────────────
	_sec_deploy = _make_section_card(tr_ui("sec_deploy"), true)
	root.add_child(_sec_deploy)
	var deploy_body := _section_body(_sec_deploy)

	# Checklist visuelle avant Launch (réduit l’incertitude)
	deploy_checklist_label = Label.new()
	deploy_checklist_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	deploy_checklist_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deploy_checklist_label.add_theme_font_size_override("font_size", _ed_font())
	deploy_checklist_label.modulate = C_MUTED
	deploy_body.add_child(deploy_checklist_label)

	# File multi-plateformes visible
	_queue_status_label = Label.new()
	_queue_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_queue_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_status_label.add_theme_font_size_override("font_size", _ed_font(-1))
	_queue_status_label.modulate = C_BUSY
	_queue_status_label.visible = false
	deploy_body.add_child(_queue_status_label)

	# Profils de déploiement
	var profile_row := HBoxContainer.new()
	profile_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deploy_body.add_child(profile_row)
	_profile_option = OptionButton.new()
	_profile_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_option.tooltip_text = tr_ui("profile_tip")
	_profile_option.item_selected.connect(_on_profile_selected)
	profile_row.add_child(_profile_option)
	_style_option_button(_profile_option)
	_profile_name_edit = LineEdit.new()
	_profile_name_edit.placeholder_text = tr_ui("profile_name_ph")
	_profile_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_row.add_child(_profile_name_edit)
	_style_line_edit(_profile_name_edit)
	var profile_btn_row := HBoxContainer.new()
	profile_btn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deploy_body.add_child(profile_btn_row)
	_profile_save_btn = Button.new()
	_profile_save_btn.text = tr_ui("profile_save")
	_profile_save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_save_btn.pressed.connect(_on_profile_save_pressed)
	profile_btn_row.add_child(_profile_save_btn)
	_style_secondary_button(_profile_save_btn)
	_profile_delete_btn = Button.new()
	_profile_delete_btn.text = tr_ui("profile_delete")
	_profile_delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_delete_btn.pressed.connect(_on_profile_delete_pressed)
	profile_btn_row.add_child(_profile_delete_btn)
	_style_secondary_button(_profile_delete_btn)

	# Bannière reprise upload après crash
	_resume_banner = PanelContainer.new()
	_resume_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resume_banner.visible = false
	var rb_sb := StyleBoxFlat.new()
	rb_sb.bg_color = Color(0.18, 0.22, 0.12, 0.94)
	rb_sb.set_corner_radius_all(10)
	rb_sb.content_margin_left = 10
	rb_sb.content_margin_right = 10
	rb_sb.content_margin_top = 8
	rb_sb.content_margin_bottom = 8
	rb_sb.border_width_left = 1
	rb_sb.border_width_right = 1
	rb_sb.border_width_top = 1
	rb_sb.border_width_bottom = 1
	rb_sb.border_color = C_OK
	_resume_banner.add_theme_stylebox_override("panel", rb_sb)
	deploy_body.add_child(_resume_banner)
	var resume_col := VBoxContainer.new()
	_resume_banner.add_child(resume_col)
	_resume_banner_label = Label.new()
	_resume_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_resume_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resume_banner_label.add_theme_font_size_override("font_size", _ed_font(-1))
	resume_col.add_child(_resume_banner_label)
	var resume_row := HBoxContainer.new()
	resume_col.add_child(resume_row)
	_resume_upload_btn = Button.new()
	_resume_upload_btn.text = tr_ui("resume_btn")
	_resume_upload_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resume_upload_btn.pressed.connect(_on_resume_upload_pressed)
	resume_row.add_child(_resume_upload_btn)
	_style_primary_button(_resume_upload_btn)
	var discard_btn := Button.new()
	discard_btn.text = tr_ui("resume_discard")
	discard_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	discard_btn.pressed.connect(_on_discard_resume_pressed)
	resume_row.add_child(discard_btn)
	_style_secondary_button(discard_btn)

	# Preflight détaillé (bloquant) — liste à puces
	_preflight_panel = PanelContainer.new()
	_preflight_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preflight_panel.visible = false
	var pf_sb := StyleBoxFlat.new()
	pf_sb.bg_color = Color(0.28, 0.12, 0.10, 0.92)
	pf_sb.set_corner_radius_all(10)
	pf_sb.content_margin_left = 10
	pf_sb.content_margin_right = 10
	pf_sb.content_margin_top = 8
	pf_sb.content_margin_bottom = 8
	pf_sb.border_width_left = 1
	pf_sb.border_width_right = 1
	pf_sb.border_width_top = 1
	pf_sb.border_width_bottom = 1
	pf_sb.border_color = C_ERR
	_preflight_panel.add_theme_stylebox_override("panel", pf_sb)
	deploy_body.add_child(_preflight_panel)
	_preflight_label = Label.new()
	_preflight_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preflight_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preflight_label.add_theme_font_size_override("font_size", _ed_font(-1))
	_preflight_panel.add_child(_preflight_label)

	deploy_btn = Button.new()
	deploy_btn.text = tr_ui("deploy")
	deploy_btn.tooltip_text = tr_ui("deploy_tip")
	deploy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deploy_btn.pressed.connect(_on_deploy_pressed)
	deploy_body.add_child(deploy_btn)
	_style_success_button(deploy_btn)

	redeploy_btn = Button.new()
	redeploy_btn.text = tr_ui("redeploy")
	redeploy_btn.tooltip_text = tr_ui("redeploy_tip")
	redeploy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	redeploy_btn.pressed.connect(_on_redeploy_pressed)
	deploy_body.add_child(redeploy_btn)
	_style_secondary_button(redeploy_btn)

	build_limit_label = Label.new()
	build_limit_label.text = tr_ui("build_limit") % MAX_BUILD_MB
	build_limit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	build_limit_label.add_theme_font_size_override("font_size", _ed_font())
	build_limit_label.modulate = C_MUTED
	deploy_body.add_child(build_limit_label)

	resubmit_btn = Button.new()
	resubmit_btn.text = tr_ui("resubmit")
	resubmit_btn.tooltip_text = tr_ui("resubmit_tip")
	resubmit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resubmit_btn.pressed.connect(_on_resubmit_pressed)
	deploy_body.add_child(resubmit_btn)
	_style_primary_button(resubmit_btn)

	var deploy_fb := _make_local_feedback()
	_fb_deploy = deploy_fb[0]
	_fb_deploy_label = deploy_fb[1]
	deploy_body.add_child(_fb_deploy)

	_row_actions = HBoxContainer.new()
	_row_actions.visible = false
	deploy_body.add_child(_row_actions)

	# Historique des deploys (local)
	_hist_label = Label.new()
	_hist_label.text = tr_ui("hist_title")
	_hist_label.add_theme_font_size_override("font_size", _ed_font())
	_hist_label.add_theme_color_override("font_color", C_SECTION)
	deploy_body.add_child(_hist_label)
	_hist_list = ItemList.new()
	_hist_list.custom_minimum_size = Vector2(0, 88)
	_hist_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hist_list.select_mode = ItemList.SELECT_SINGLE
	_hist_list.allow_reselect = true
	deploy_body.add_child(_hist_list)

	# ── 6. MARKETING ────────────────────────────────────────────────────────
	_sec_share = _make_section_card(tr_ui("sec_share"), false)
	root.add_child(_sec_share)
	var share_body := _section_body(_sec_share)

	store_base_edit = LineEdit.new()
	store_base_edit.placeholder_text = tr_ui("store_base_ph")
	store_base_edit.tooltip_text = tr_ui("store_base_tip")
	store_base_edit.text = "https://www.thiossane.store/"
	store_base_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_body.add_child(store_base_edit)
	_style_line_edit(store_base_edit)

	share_label_edit = LineEdit.new()
	share_label_edit.placeholder_text = tr_ui("share_label_ph")
	share_label_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_body.add_child(share_label_edit)
	_style_line_edit(share_label_edit)

	campaign_edit = LineEdit.new()
	campaign_edit.placeholder_text = tr_ui("campaign_ph")
	campaign_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_body.add_child(campaign_edit)
	_style_line_edit(campaign_edit)

	channel_edit = LineEdit.new()
	channel_edit.placeholder_text = tr_ui("channel_ph")
	channel_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_body.add_child(channel_edit)
	_style_line_edit(channel_edit)

	share_force_check = CheckBox.new()
	share_force_check.text = tr_ui("share_force_new")
	share_body.add_child(share_force_check)
	_style_checkbox(share_force_check)

	share_generate_btn = Button.new()
	share_generate_btn.text = tr_ui("share_generate")
	share_generate_btn.tooltip_text = tr_ui("share_generate_tip")
	share_generate_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_generate_btn.pressed.connect(_on_share_generate_pressed)
	share_body.add_child(share_generate_btn)
	_style_primary_button(share_generate_btn)
	if is_instance_valid(amb_generate_btn):
		_style_primary_button(amb_generate_btn)
	if is_instance_valid(amb_copy_btn):
		_style_secondary_button(amb_copy_btn)
	if is_instance_valid(amb_stats_btn):
		_style_secondary_button(amb_stats_btn)

	share_url_edit = LineEdit.new()
	share_url_edit.placeholder_text = tr_ui("share_empty")
	share_url_edit.editable = false
	share_url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_body.add_child(share_url_edit)
	_style_line_edit(share_url_edit)

	share_stats_label = Label.new()
	share_stats_label.text = tr_ui("share_stats_line") % [0, 0]
	share_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	share_stats_label.add_theme_font_size_override("font_size", _ed_font())
	share_stats_label.modulate = C_MUTED
	share_body.add_child(share_stats_label)

	var share_actions := HBoxContainer.new()
	share_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_actions.add_theme_constant_override("separation", 12)
	share_body.add_child(share_actions)

	share_copy_link_btn = Button.new()
	share_copy_link_btn.text = tr_ui("share_copy_link")
	share_copy_link_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_copy_link_btn.pressed.connect(_on_share_copy_link)
	share_actions.add_child(share_copy_link_btn)
	_style_secondary_button(share_copy_link_btn)

	# Liens store prêts à coller (Discord / WhatsApp / page jeu)
	var quick_links := HFlowContainer.new()
	quick_links.add_theme_constant_override("h_separation", 8)
	quick_links.add_theme_constant_override("v_separation", 6)
	share_body.add_child(quick_links)
	_copy_store_btn = Button.new()
	_copy_store_btn.text = tr_ui("link_store")
	_copy_store_btn.tooltip_text = tr_ui("link_store_tip")
	_copy_store_btn.pressed.connect(_on_copy_store_page)
	quick_links.add_child(_copy_store_btn)
	_style_secondary_button(_copy_store_btn)
	_copy_discord_btn = Button.new()
	_copy_discord_btn.text = tr_ui("link_discord")
	_copy_discord_btn.tooltip_text = tr_ui("link_discord_tip")
	_copy_discord_btn.pressed.connect(_on_copy_discord_blurb)
	quick_links.add_child(_copy_discord_btn)
	_style_secondary_button(_copy_discord_btn)
	_copy_whatsapp_btn = Button.new()
	_copy_whatsapp_btn.text = tr_ui("link_whatsapp")
	_copy_whatsapp_btn.tooltip_text = tr_ui("link_whatsapp_tip")
	_copy_whatsapp_btn.pressed.connect(_on_copy_whatsapp_blurb)
	quick_links.add_child(_copy_whatsapp_btn)
	_style_secondary_button(_copy_whatsapp_btn)

	share_stats_btn = Button.new()
	share_stats_btn.text = tr_ui("share_stats_refresh")
	share_stats_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_stats_btn.pressed.connect(_on_share_stats_pressed)
	share_actions.add_child(share_stats_btn)
	_style_secondary_button(share_stats_btn)

	mkt_analytics_btn = Button.new()
	mkt_analytics_btn.text = tr_ui("mkt_analytics")
	mkt_analytics_btn.tooltip_text = tr_ui("mkt_analytics_tip")
	mkt_analytics_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mkt_analytics_btn.pressed.connect(_on_mkt_analytics_pressed)
	share_body.add_child(mkt_analytics_btn)
	_style_secondary_button(mkt_analytics_btn)

	mkt_sales_label = Label.new()
	mkt_sales_label.text = _fmt("mkt_sales_line", [0, 0.0])
	mkt_sales_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mkt_sales_label.add_theme_font_size_override("font_size", _ed_font())
	mkt_sales_label.modulate = C_MUTED
	share_body.add_child(mkt_sales_label)

	# ── Ambassadeurs (liens ciblés joueur) ───────────────────────────────────
	var amb_sep := HSeparator.new()
	share_body.add_child(amb_sep)

	var amb_title := Label.new()
	amb_title.text = tr_ui("amb_title")
	amb_title.add_theme_font_size_override("font_size", _ed_font() + 1)
	amb_title.modulate = C_TEXT
	share_body.add_child(amb_title)

	var amb_hint := Label.new()
	amb_hint.text = tr_ui("amb_hint")
	amb_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	amb_hint.add_theme_font_size_override("font_size", _ed_font())
	amb_hint.modulate = C_MUTED
	share_body.add_child(amb_hint)

	amb_email_edit = LineEdit.new()
	amb_email_edit.placeholder_text = tr_ui("amb_email_ph")
	amb_email_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_body.add_child(amb_email_edit)
	_style_line_edit(amb_email_edit)

	amb_label_edit = LineEdit.new()
	amb_label_edit.placeholder_text = tr_ui("amb_label_ph")
	amb_label_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_body.add_child(amb_label_edit)
	_style_line_edit(amb_label_edit)

	amb_invite_check = CheckBox.new()
	amb_invite_check.text = tr_ui("amb_invite")
	amb_invite_check.button_pressed = false
	share_body.add_child(amb_invite_check)
	_style_checkbox(amb_invite_check)

	amb_generate_btn = Button.new()
	amb_generate_btn.text = tr_ui("amb_generate")
	amb_generate_btn.tooltip_text = tr_ui("amb_generate_tip")
	amb_generate_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amb_generate_btn.pressed.connect(_on_ambassador_generate_pressed)
	share_body.add_child(amb_generate_btn)
	_style_primary_button(amb_generate_btn)

	amb_url_edit = LineEdit.new()
	amb_url_edit.placeholder_text = tr_ui("amb_empty")
	amb_url_edit.editable = false
	amb_url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_body.add_child(amb_url_edit)
	_style_line_edit(amb_url_edit)

	var amb_actions := HBoxContainer.new()
	amb_actions.add_theme_constant_override("separation", 10)
	share_body.add_child(amb_actions)

	amb_copy_btn = Button.new()
	amb_copy_btn.text = tr_ui("amb_copy")
	amb_copy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amb_copy_btn.pressed.connect(_on_ambassador_copy)
	amb_actions.add_child(amb_copy_btn)
	_style_secondary_button(amb_copy_btn)

	amb_stats_btn = Button.new()
	amb_stats_btn.text = tr_ui("amb_stats")
	amb_stats_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amb_stats_btn.pressed.connect(_on_ambassador_stats_pressed)
	amb_actions.add_child(amb_stats_btn)
	_style_secondary_button(amb_stats_btn)

	amb_stats_label = Label.new()
	amb_stats_label.text = tr_ui("amb_stats_line") % [0, 0, 0, 0]
	amb_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	amb_stats_label.add_theme_font_size_override("font_size", _ed_font())
	amb_stats_label.modulate = C_MUTED
	share_body.add_child(amb_stats_label)


	# ── 8. SUPPORT ──────────────────────────────────────────────────────────
	_sec_support = _make_section_card(tr_ui("sec_support"), false)
	root.add_child(_sec_support)
	var support_body := _section_body(_sec_support)

	var cat_lbl := Label.new()
	cat_lbl.text = tr_ui("support_cat")
	cat_lbl.add_theme_font_size_override("font_size", _ed_font())
	cat_lbl.modulate = C_MUTED
	support_body.add_child(cat_lbl)

	support_category = OptionButton.new()
	support_category.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_support_fill_categories()
	support_body.add_child(support_category)

	support_subject_edit = LineEdit.new()
	support_subject_edit.placeholder_text = tr_ui("support_subject_ph")
	support_subject_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	support_body.add_child(support_subject_edit)
	_style_line_edit(support_subject_edit)

	support_body_edit = TextEdit.new()
	support_body_edit.placeholder_text = tr_ui("support_body_ph")
	support_body_edit.custom_minimum_size.y = 90
	support_body_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	support_body_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	support_body.add_child(support_body_edit)
	_style_text_edit(support_body_edit)

	var support_btn_row := HBoxContainer.new()
	support_btn_row.add_theme_constant_override("separation", 10)
	support_body.add_child(support_btn_row)

	support_submit_btn = Button.new()
	support_submit_btn.text = tr_ui("support_submit")
	support_submit_btn.tooltip_text = tr_ui("support_submit_tip")
	support_submit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	support_submit_btn.pressed.connect(_on_support_submit)
	support_btn_row.add_child(support_submit_btn)
	_style_primary_button(support_submit_btn)

	support_refresh_btn = Button.new()
	support_refresh_btn.text = tr_ui("support_refresh")
	support_refresh_btn.tooltip_text = tr_ui("support_refresh_tip")
	support_refresh_btn.pressed.connect(_on_support_refresh)
	support_btn_row.add_child(support_refresh_btn)
	_style_secondary_button(support_refresh_btn)

	support_list = ItemList.new()
	support_list.custom_minimum_size.y = 100
	support_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	support_list.item_selected.connect(_on_support_ticket_selected)
	support_body.add_child(support_list)

	support_detail_label = Label.new()
	support_detail_label.text = tr_ui("support_select")
	support_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	support_detail_label.add_theme_font_size_override("font_size", _ed_font(-1))
	support_detail_label.modulate = C_MUTED
	support_body.add_child(support_detail_label)

	support_reply_edit = TextEdit.new()
	support_reply_edit.placeholder_text = tr_ui("support_reply_ph")
	support_reply_edit.custom_minimum_size.y = 60
	support_reply_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	support_body.add_child(support_reply_edit)
	_style_text_edit(support_reply_edit)

	support_reply_btn = Button.new()
	support_reply_btn.text = tr_ui("support_reply")
	support_reply_btn.pressed.connect(_on_support_reply)
	support_body.add_child(support_reply_btn)
	_style_secondary_button(support_reply_btn)

	# Notifications : pas de section dédiée — badges sur les sections concernées
	_notif_poll_timer = Timer.new()
	_notif_poll_timer.wait_time = 60.0
	_notif_poll_timer.one_shot = false
	_notif_poll_timer.timeout.connect(_on_notif_refresh)
	add_child(_notif_poll_timer)

	# ── 7. PROGRESSION & JOURNAL ────────────────────────────────────────────
	_sec_prog = _make_section_card(tr_ui("sec_prog"), true)
	root.add_child(_sec_prog)
	var prog_body := _section_body(_sec_prog)

	step_label = Label.new()
	step_label.text = tr_ui("step_idle")
	step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step_label.add_theme_font_size_override("font_size", _ed_font())
	step_label.modulate = C_MUTED
	prog_body.add_child(step_label)

	progress_bar = ProgressBar.new()
	progress_bar.max_value = 100
	progress_bar.value = 0
	progress_bar.show_percentage = true
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.custom_minimum_size.y = 12
	prog_body.add_child(progress_bar)

	upload_detail_label = Label.new()
	upload_detail_label.text = ""
	upload_detail_label.visible = false
	upload_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	upload_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upload_detail_label.add_theme_font_size_override("font_size", _ed_font(-1))
	upload_detail_label.modulate = C_MUTED
	prog_body.add_child(upload_detail_label)

	var log_header := HBoxContainer.new()
	log_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_header.add_theme_constant_override("separation", 10)
	prog_body.add_child(log_header)
	var log_title := Label.new()
	log_title.text = tr_ui("journal")
	_log_title = log_title
	log_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_title.add_theme_font_size_override("font_size", _ed_font(1))
	log_title.add_theme_color_override("font_color", C_SECTION)
	log_header.add_child(log_title)
	var clear_log_btn := Button.new()
	clear_log_btn.text = tr_ui("clear_log")
	_clear_log_btn = clear_log_btn
	clear_log_btn.tooltip_text = tr_ui("clear_log_tip")
	clear_log_btn.pressed.connect(func():
		log_edit.text = ""
		_log_line_count = 0)
	log_header.add_child(clear_log_btn)
	_style_secondary_button(clear_log_btn)

	log_edit = TextEdit.new()
	log_edit.editable = false
	log_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	log_edit.custom_minimum_size.y = 200
	log_edit.placeholder_text = tr_ui("log_ph")
	log_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prog_body.add_child(log_edit)
	_style_text_edit(log_edit)

	# Ancien status_label bas de page : masqué — feedback local près des boutons
	status_label = Label.new()
	status_label.visible = false
	status_label.text = ""
	root.add_child(status_label)

	var footer := Label.new()
	footer.text = tr_ui("footer")
	_footer_label = footer
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.modulate = C_MUTED
	footer.add_theme_font_size_override("font_size", _ed_font(-2))
	root.add_child(footer)

	# Badges notification (boule) sur les sections concernées
	_attach_section_badges()
	_refresh_game_status_ui()
	_update_deploy_checklist()
	# Checklist live quand les plateformes changent
	if is_instance_valid(platform_web):
		platform_web.toggled.connect(func(_on: bool) -> void: _update_deploy_checklist())
	if is_instance_valid(platform_windows):
		platform_windows.toggled.connect(func(_on: bool) -> void: _update_deploy_checklist())
	if is_instance_valid(platform_android):
		platform_android.toggled.connect(func(_on: bool) -> void: _update_deploy_checklist())
	if is_instance_valid(preset_web):
		preset_web.item_selected.connect(func(_i: int) -> void: _update_deploy_checklist())
	if is_instance_valid(preset_windows):
		preset_windows.item_selected.connect(func(_i: int) -> void: _update_deploy_checklist())
	if is_instance_valid(preset_android):
		preset_android.item_selected.connect(func(_i: int) -> void: _update_deploy_checklist())
	if is_instance_valid(title_edit):
		title_edit.text_changed.connect(func(_t: String) -> void: _update_deploy_checklist())
	if is_instance_valid(version_edit):
		version_edit.text_changed.connect(func(_t: String) -> void: _update_deploy_checklist())

	# HTTP — use_threads explicite + timeout, enfants du dock (requis pour l'éditeur)
	http = HTTPRequest.new()
	http.timeout = 60
	http.use_threads = true
	http.request_completed.connect(_on_http_completed)
	add_child(http)

	upload_http = HTTPRequest.new()
	upload_http.timeout = 600
	upload_http.use_threads = true
	upload_http.request_completed.connect(_on_upload_completed)
	add_child(upload_http)


func _section_header(text: String) -> Control:
	## Conservé : délègue à la carte repliable (ouverte par défaut).
	return _make_section_card(text, true)


func _make_card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_CARD.r, C_CARD.g, C_CARD.b, 0.94)
	sb.set_corner_radius_all(_t_radius_card)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	sb.border_width_left = _t_border_w
	sb.border_width_right = _t_border_w
	sb.border_width_top = _t_border_w
	sb.border_width_bottom = _t_border_w
	sb.border_color = C_BORDER
	sb.shadow_color = Color(0, 0, 0, _t_shadow_alpha)
	sb.shadow_size = _t_shadow_size
	sb.shadow_offset = Vector2(0, maxi(1, int(_t_shadow_size * 0.35)))
	sb.anti_aliasing = true
	return sb


func _make_section_card(title: String, start_open: bool = true) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_card_style())

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	card.add_child(col)

	# Rangée d'en-tête : bouton (titre) + emplacement pour badge (ex. notif)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 8)
	head_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(head_row)

	var head := Button.new()
	head.toggle_mode = true
	head.button_pressed = start_open
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.set_meta("sec_title", title)
	_style_section_header(head)
	_refresh_section_header(head)
	head_row.add_child(head)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 14)
	pad.visible = start_open
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(pad)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	pad.add_child(inner)

	head.toggled.connect(func(on: bool) -> void:
		pad.visible = on
		_refresh_section_header(head)
	)

	card.set_meta("header_btn", head)
	card.set_meta("header_row", head_row)
	card.set_meta("body", inner)
	card.set_meta("pad", pad)
	return card


func _section_body(card: Control) -> VBoxContainer:
	if is_instance_valid(card) and card.has_meta("body"):
		return card.get_meta("body") as VBoxContainer
	return null


func _refresh_section_header(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	var title := str(btn.get_meta("sec_title", ""))
	btn.text = ("%s  %s" % ["▾" if btn.button_pressed else "▸", title]).strip_edges()


func _style_section_header(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	btn.custom_minimum_size.y = 42
	btn.add_theme_font_size_override("font_size", _ed_font(1))
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0, 0, 0, 0)
	n.set_corner_radius_all(0)
	n.content_margin_left = 14
	n.content_margin_right = 14
	n.content_margin_top = 10
	n.content_margin_bottom = 10
	n.border_width_bottom = 1
	n.border_color = C_BORDER
	n.anti_aliasing = true
	var hover := n.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.04)
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", n)
	btn.add_theme_stylebox_override("focus", n)
	btn.add_theme_color_override("font_color", C_PRIMARY)
	btn.add_theme_color_override("font_hover_color", Color(0.97, 0.84, 0.48))
	btn.add_theme_color_override("font_pressed_color", C_PRIMARY)


func _make_field_sb(focused: bool = false, readonly: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_CARD.r * 0.7, C_CARD.g * 0.7, C_CARD.b * 0.7, 0.96) if readonly else C_SURFACE
	sb.set_corner_radius_all(_t_radius_field)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.border_width_left = _t_border_w
	sb.border_width_right = _t_border_w
	sb.border_width_top = _t_border_w
	sb.border_width_bottom = _t_border_w
	sb.border_color = C_PRIMARY if focused else C_BORDER
	sb.anti_aliasing = true
	return sb


func _style_line_edit(edit: LineEdit) -> void:
	if not is_instance_valid(edit):
		return
	edit.custom_minimum_size.y = 42
	edit.add_theme_font_size_override("font_size", _ed_font())
	edit.add_theme_stylebox_override("normal", _make_field_sb(false, false))
	edit.add_theme_stylebox_override("focus", _make_field_sb(true, false))
	edit.add_theme_stylebox_override("read_only", _make_field_sb(false, true))
	edit.add_theme_color_override("font_color", C_TEXT)
	edit.add_theme_color_override("font_placeholder_color", C_MUTED)
	edit.add_theme_color_override("font_uneditable_color", C_MUTED)
	edit.add_theme_color_override("caret_color", C_PRIMARY)


func _style_text_edit(edit: TextEdit) -> void:
	if not is_instance_valid(edit):
		return
	edit.add_theme_font_size_override("font_size", _ed_font())
	# Mono-ish denser look for PS2 / CRT logs
	if (_ui_theme in ["ps2", "underground", "matrix"] or _crt_enabled) and edit == log_edit:
		edit.add_theme_font_size_override("font_size", _ed_font(-1))
	var n := _make_field_sb(false, not edit.editable)
	var f := _make_field_sb(true, not edit.editable)
	edit.add_theme_stylebox_override("normal", n)
	edit.add_theme_stylebox_override("focus", f)
	edit.add_theme_stylebox_override("read_only", _make_field_sb(false, true))
	edit.add_theme_color_override("font_color", C_TEXT)
	edit.add_theme_color_override("font_readonly_color", C_TEXT)
	edit.add_theme_color_override("font_placeholder_color", C_MUTED)
	edit.add_theme_color_override("caret_color", C_PRIMARY)


func _style_option_button(btn: OptionButton) -> void:
	if not is_instance_valid(btn):
		return
	btn.custom_minimum_size.y = 42
	btn.add_theme_font_size_override("font_size", _ed_font())
	var n := _make_field_sb(false)
	var h := n.duplicate() as StyleBoxFlat
	h.border_color = C_PRIMARY
	h.bg_color = Color(0.22, 0.23, 0.26)
	var f := _make_field_sb(true)
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	btn.add_theme_stylebox_override("focus", f)
	btn.add_theme_stylebox_override("disabled", _make_field_sb(false, true))
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_color_override("font_hover_color", C_PRIMARY)
	btn.add_theme_color_override("font_pressed_color", C_PRIMARY)
	btn.add_theme_color_override("font_disabled_color", C_MUTED)
	btn.add_theme_color_override("font_focus_color", C_TEXT)


func _style_spinbox(sb: SpinBox) -> void:
	if not is_instance_valid(sb):
		return
	sb.custom_minimum_size.y = 42
	sb.add_theme_font_size_override("font_size", _ed_font())
	var le := sb.get_line_edit()
	if is_instance_valid(le):
		_style_line_edit(le)


func _style_checkbox(cb: CheckBox) -> void:
	if not is_instance_valid(cb):
		return
	cb.add_theme_font_size_override("font_size", _ed_font())
	cb.add_theme_color_override("font_color", C_TEXT)
	cb.add_theme_color_override("font_hover_color", C_PRIMARY)
	cb.add_theme_color_override("font_pressed_color", C_PRIMARY)


func _set_conn_dot_color(c: Color) -> void:
	if not is_instance_valid(_conn_dot):
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(8)
	sb.anti_aliasing = true
	_conn_dot.add_theme_stylebox_override("panel", sb)


func _section_label(text: String) -> Label:
	# Conservé pour compatibilité éventuelle
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _ed_font(2))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _ensure_section_open(card: Control) -> void:
	if not is_instance_valid(card) or not card.has_meta("header_btn"):
		return
	var btn: Button = card.get_meta("header_btn")
	if is_instance_valid(btn) and not btn.button_pressed:
		btn.button_pressed = true


func _plat_row_container() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	return row


## Bascule empilement vertical / horizontal selon la largeur (responsive).
## Seuil ~340 px adapté au dock droit Godot (souvent 260–400 px).
func _on_panel_resized() -> void:
	var w := size.x
	if w < 8.0:
		return
	var narrow := w < LAYOUT_NARROW_PX
	var compact := w < LAYOUT_COMPACT_PX
	_layout_narrow = narrow

	# Marges plus serrées en dock étroit
	if is_instance_valid(_content_margin):
		var m := 6 if compact else (8 if narrow else 10)
		_content_margin.add_theme_constant_override("margin_left", m)
		_content_margin.add_theme_constant_override("margin_right", m)
		_content_margin.add_theme_constant_override("margin_top", 6 if compact else 8)
		_content_margin.add_theme_constant_override("margin_bottom", 8 if compact else 10)

	if is_instance_valid(_content_root):
		_content_root.add_theme_constant_override("separation", 10 if narrow else 12)

	# Titre un peu plus petit en compact
	if is_instance_valid(_ui_title):
		_ui_title.add_theme_font_size_override("font_size", _ed_font(2 if compact else 4))

	# Outils header : min sizes adaptés
	if is_instance_valid(_theme_option):
		_theme_option.custom_minimum_size = Vector2(72 if compact else (90 if narrow else 100), 0)
	if is_instance_valid(_lang_btn):
		_lang_btn.custom_minimum_size = Vector2(36 if compact else 40, 0)
	if is_instance_valid(_music_play_btn):
		_music_play_btn.custom_minimum_size = Vector2(32 if compact else 36, 0)

	# Lignes principales : empiler si étroit
	_stack_or_row(_row_auth, narrow)
	_stack_or_row(_row_title_ver, narrow)
	_stack_or_row(_row_cat_price, narrow)
	_stack_or_row(_row_checks, narrow)
	_stack_or_row(_row_actions, narrow)

	# Plateformes : checkbox au-dessus du preset si étroit
	if is_instance_valid(_plat_grid):
		for row in _plat_grid.get_children():
			if row is BoxContainer:
				_stack_or_row(row as Control, narrow)

	if is_instance_valid(log_edit):
		log_edit.custom_minimum_size.y = 120 if compact else (150 if narrow else 200)
	if is_instance_valid(desc_edit):
		desc_edit.custom_minimum_size.y = 56 if compact else (64 if narrow else 80)

	# Champs qui ne doivent pas forcer une largeur min trop grande
	for edit in [email_edit, password_edit, title_edit, version_edit, price_edit]:
		if is_instance_valid(edit):
			edit.custom_minimum_size.x = 0
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_instance_valid(category_option):
		category_option.custom_minimum_size.x = 0
		category_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for preset in [preset_web, preset_windows, preset_android]:
		if is_instance_valid(preset):
			preset.custom_minimum_size.x = 0
			preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Mascotte : adapter la bulle et repositionner si visible
	if _mascot_visible and is_instance_valid(_mascot_root):
		_mascot_apply_bubble_size()
		_mascot_root.position = _mascot_bottom_right()
		_mascot_start_idle()


## Remplace un HBox par un VBox (ou inverse) en conservant les enfants.
	if _tag_image != null:
		_tag_resize_image_if_needed()
	if _crt_enabled:
		_crt_layout_vignette()
	if _rain_enabled:
		_rain_layout()

func _stack_or_row(box: Control, vertical: bool) -> void:
	if not is_instance_valid(box) or box.get_parent() == null:
		return
	var want_v := vertical
	var is_v := box is VBoxContainer
	var is_h := box is HBoxContainer
	if want_v and is_v:
		return
	if (not want_v) and is_h:
		return
	# Ne toucher qu'aux HBox/VBox (pas FlowContainer etc.)
	if not is_v and not is_h:
		return

	var parent: Node = box.get_parent()
	var idx := box.get_index()
	var children: Array = []
	for c in box.get_children():
		children.append(c)

	var replacement: BoxContainer
	if want_v:
		replacement = VBoxContainer.new()
	else:
		replacement = HBoxContainer.new()
	replacement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	replacement.add_theme_constant_override("separation", 8 if want_v else 10)
	replacement.name = box.name

	for c in children:
		box.remove_child(c)
		if c is Control:
			var ctrl := c as Control
			ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# En vertical, chaque enfant prend toute la largeur
			if want_v:
				ctrl.custom_minimum_size.x = 0
		replacement.add_child(c)

	# Mettre à jour les refs connues
	if box == _row_auth:
		_row_auth = replacement
	elif box == _row_title_ver:
		_row_title_ver = replacement
	elif box == _row_cat_price:
		_row_cat_price = replacement
	elif box == _row_checks:
		_row_checks = replacement
	elif box == _row_actions:
		_row_actions = replacement

	parent.remove_child(box)
	box.queue_free()
	parent.add_child(replacement)
	parent.move_child(replacement, idx)




# ══════════════════════════════════════════════════════════════════════════════
# ONBOARDING (première session)
# ══════════════════════════════════════════════════════════════════════════════

func _onboarding_step_states() -> Array:
	## 5 bools : auth, game, fiche, plateformes, prêt à deploy
	var auth_ok := access_token != ""
	var game_ok := selected_game_id >= 1
	var fiche_ok := is_instance_valid(title_edit) and title_edit.text.strip_edges() != "" \
		and is_instance_valid(version_edit) and version_edit.text.strip_edges() != ""
	var any_plat := false
	var preset_ok := true
	if is_instance_valid(platform_web) and platform_web.button_pressed:
		any_plat = true
		if not is_instance_valid(preset_web) or preset_web.get_selected_id() < 0 \
				or str(preset_web.get_item_text(preset_web.selected)).begins_with("—"):
			preset_ok = false
	if is_instance_valid(platform_windows) and platform_windows.button_pressed:
		any_plat = true
		if not is_instance_valid(preset_windows) or preset_windows.get_selected_id() < 0 \
				or str(preset_windows.get_item_text(preset_windows.selected)).begins_with("—"):
			preset_ok = false
	if is_instance_valid(platform_android) and platform_android.button_pressed:
		any_plat = true
		if not is_instance_valid(preset_android) or preset_android.get_selected_id() < 0 \
				or str(preset_android.get_item_text(preset_android.selected)).begins_with("—"):
			preset_ok = false
	var plat_ok := any_plat and preset_ok
	var ready_ok := auth_ok and game_ok and fiche_ok and plat_ok
	return [auth_ok, game_ok, fiche_ok, plat_ok, ready_ok]


func _refresh_onboarding() -> void:
	if not is_instance_valid(_onboarding_panel):
		return
	# Visibilité sections avancées
	_apply_onboarding_visibility()

	if _onboarding_done:
		_onboarding_panel.visible = false
		return

	_onboarding_panel.visible = true
	var states: Array = _onboarding_step_states()
	var labels := [
		tr_ui("ob_step_auth"),
		tr_ui("ob_step_game"),
		tr_ui("ob_step_fiche"),
		tr_ui("ob_step_plat"),
		tr_ui("ob_step_deploy"),
	]
	var next_idx := 0
	for i in range(mini(5, _onboarding_step_btns.size())):
		var ok: bool = bool(states[i]) if i < states.size() else false
		var btn: Button = _onboarding_step_btns[i]
		if not is_instance_valid(btn):
			continue
		var mark := "✔" if ok else "○"
		btn.text = "%s  %s" % [mark, labels[i]]
		btn.modulate = C_OK if ok else C_TEXT
		if not ok and next_idx == 0:
			next_idx = i
		if ok:
			next_idx = i + 1
	# next_idx = first incomplete, or 5 if all done
	var first_bad := 0
	for i in range(states.size()):
		if not states[i]:
			first_bad = i
			break
		first_bad = i + 1

	if first_bad >= 5:
		_onboarding_next.text = tr_ui("ob_next_ready")
		if is_instance_valid(_onboarding_dismiss_btn):
			_onboarding_dismiss_btn.visible = true
		if is_instance_valid(_onboarding_skip_btn):
			_onboarding_skip_btn.visible = false
	else:
		var next_msgs := [
			tr_ui("ob_next_auth"),
			tr_ui("ob_next_game"),
			tr_ui("ob_next_fiche"),
			tr_ui("ob_next_plat"),
			tr_ui("ob_next_deploy"),
		]
		_onboarding_next.text = next_msgs[first_bad]
		if is_instance_valid(_onboarding_dismiss_btn):
			_onboarding_dismiss_btn.visible = false
		if is_instance_valid(_onboarding_skip_btn):
			_onboarding_skip_btn.visible = true


func _apply_onboarding_visibility() -> void:
	## Pendant l'onboarding : masquer marketing / support / wellbeing.
	var show_advanced := _onboarding_done
	for sec in [_sec_share, _sec_support, _sec_music, _sec_video]:
		if is_instance_valid(sec):
			sec.visible = show_advanced


func _onboarding_focus_sections(step: int) -> void:
	## Ouvre la section utile, replie le superflu (sans forcer à chaque frame si déjà ok).
	if _onboarding_done:
		return
	# Toujours montrer connexion + progression
	# step 0: conn ; 1: game ; 2: fiche ; 3: plat ; 4+: deploy
	var map := {
		0: _sec_conn,
		1: _sec_game,
		2: _sec_fiche,
		3: _sec_plat,
		4: _sec_deploy,
	}
	if map.has(step):
		_ensure_section_open(map[step])


func _on_onboarding_step_pressed(step: int) -> void:
	var sections := [_sec_conn, _sec_game, _sec_fiche, _sec_plat, _sec_deploy]
	if step >= 0 and step < sections.size():
		_ensure_section_open(sections[step])
	match step:
		0:
			if is_instance_valid(email_edit):
				email_edit.grab_focus()
		1:
			if is_instance_valid(game_option):
				game_option.grab_focus()
		2:
			if is_instance_valid(title_edit):
				title_edit.grab_focus()
		3:
			if is_instance_valid(platform_windows):
				platform_windows.grab_focus()
		4:
			if is_instance_valid(deploy_btn):
				deploy_btn.grab_focus()
	_feedback(tr_ui("ob_step_hint") % (step + 1), "info")


func _on_onboarding_skip() -> void:
	_onboarding_done = true
	_save_config()
	_refresh_onboarding()
	_feedback(tr_ui("ob_skipped"), "ok")
	_log(tr_ui("ob_skipped"), "ok")


func _complete_onboarding_if_needed() -> void:
	if _onboarding_done:
		return
	_onboarding_done = true
	_save_config()
	_refresh_onboarding()
	_feedback(tr_ui("ob_completed"), "ok")
	_log(tr_ui("ob_completed"), "ok")
	# Petite invitation Chaos après le premier succès (non bloquant)
	if _chaos_on_success and not _chaos_active:
		get_tree().create_timer(1.8).timeout.connect(func() -> void:
			if is_inside_tree() and not _chaos_active and not _celeb_active and is_instance_valid(_tip_label):
				_tip_label.text = "💥 " + tr_ui("ob_chaos_hint")
		)


# ══════════════════════════════════════════════════════════════════════════════
# CONFIG / TOKEN
# ══════════════════════════════════════════════════════════════════════════════

func _load_secure_tokens() -> void:
	## Délègue à core/config.gd (format unifié + migrations).
	var t: Dictionary = _Config.load_secure_tokens()
	access_token = str(t.get("access_token", ""))
	refresh_token = str(t.get("refresh_token", ""))


func _save_secure_tokens() -> void:
	if not _Config.save_secure_tokens(access_token, refresh_token):
		_log("Échec écriture stockage sécurisé tokens.")


func _clear_secure_tokens() -> void:
	access_token = ""
	refresh_token = ""
	_Config.clear_secure_tokens()


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		_ship_ensure_week()
		_load_secure_tokens()
		_onboarding_done = false
		return
	api_base_edit.text = str(cfg.get_value(CONFIG_SECTION, "api_base", "https://api.thiossane.store/api"))
	# Migration : ancienne URL locale par défaut -> backend de production
	if api_base_edit.text.strip_edges().trim_suffix("/") in ["http://127.0.0.1:8000/api", "http://localhost:8000/api"]:
		api_base_edit.text = "https://api.thiossane.store/api"
	else:
		api_base_edit.text = _api_base()
	email_edit.text = str(cfg.get_value(CONFIG_SECTION, "email", ""))
	selected_game_id = int(cfg.get_value(CONFIG_SECTION, "last_game_id", -1))
	if is_instance_valid(store_base_edit):
		store_base_edit.text = str(cfg.get_value(CONFIG_SECTION, "store_base", "https://www.thiossane.store/"))
		if "thiossane.sn" in store_base_edit.text:
			store_base_edit.text = "https://www.thiossane.store/"
	_ship_total = int(cfg.get_value(CONFIG_SECTION, "ship_total", 0))
	_ship_week_count = int(cfg.get_value(CONFIG_SECTION, "ship_week_count", 0))
	_ship_week_key = str(cfg.get_value(CONFIG_SECTION, "ship_week_key", ""))
	_ship_ensure_week()
	# Presets utilisateur
	_user_themes.clear()
	var ut_raw := str(cfg.get_value(CONFIG_SECTION, "user_themes_json", "{}"))
	var ut_parsed = JSON.parse_string(ut_raw)
	if typeof(ut_parsed) == TYPE_DICTIONARY:
		for n in ut_parsed.keys():
			var d := _theme_dict_from_json(str(ut_parsed[n]))
			if not d.is_empty():
				_user_themes[str(n)] = d
	var saved_theme := str(cfg.get_value(CONFIG_SECTION, "ui_theme", "circe"))
	var valid_themes := ["circe", "sakura", "onyx", "ivory", "ember", "matrix", "forest", "ps2", "underground", "chicago30", "gangster90", "gangsta00", "teranga", "wax", "sahel", "savane", "synthwave", "cyberpunk", "steampunk", "horror", "minimal", "pixel", "vaporwave", "manga", "ocean", "brutalist", "western", "comicbook", "custom", "default", "sunrise", "sepia"]
	if saved_theme.begins_with("user:") or saved_theme in valid_themes:
		_ui_theme = saved_theme
		_apply_theme(_ui_theme, false)
		_sync_theme_option()
	else:
		_apply_theme("circe", false)
		_sync_theme_option()
	_music_path = str(cfg.get_value(CONFIG_SECTION, "music_path", ""))
	_music_volume_db = float(cfg.get_value(CONFIG_SECTION, "music_vol", -6.0))
	_music_loop = bool(cfg.get_value(CONFIG_SECTION, "music_loop", true))
	_cozy_mode = bool(cfg.get_value(CONFIG_SECTION, "cozy_mode", false))
	_festive_enabled = bool(cfg.get_value(CONFIG_SECTION, "festive_enabled", true))
	_quote_shown_day = str(cfg.get_value(CONFIG_SECTION, "quote_day", ""))
	var pl_raw = cfg.get_value(CONFIG_SECTION, "music_playlist", [])
	_music_playlist = []
	if typeof(pl_raw) == TYPE_ARRAY:
		for p in pl_raw:
			var ps := str(p)
			if ps != "" and FileAccess.file_exists(ps):
				_music_playlist.append(ps)
	# Migration : ancien music_path seul → playlist
	if _music_playlist.is_empty() and _music_path != "" and FileAccess.file_exists(_music_path):
		_music_playlist.append(_music_path)
	_music_pl_index = int(cfg.get_value(CONFIG_SECTION, "music_pl_index", 0))
	if _music_playlist.size() > 0:
		_music_pl_index = clampi(_music_pl_index, 0, _music_playlist.size() - 1)
		_music_path = str(_music_playlist[_music_pl_index])
	else:
		_music_pl_index = -1
	if is_instance_valid(_music_vol):
		_music_vol.value = _music_volume_db
	if is_instance_valid(_music_player):
		_music_player.volume_db = _music_volume_db
	if is_instance_valid(_music_loop_check):
		_music_loop_check.button_pressed = _music_loop
	_music_playlist_refresh_ui()
	_music_update_label()
	_music_sync_ui()
	# Tokens hors .cfg
	_load_secure_tokens()
	_onboarding_done = bool(cfg.get_value(CONFIG_SECTION, "onboarding_done", false))
	# Si déjà shipé auparavant, onboarding considéré fait
	if int(cfg.get_value(CONFIG_SECTION, "ship_total", 0)) > 0:
		_onboarding_done = true
	_chaos_intensity = float(cfg.get_value(CONFIG_SECTION, "chaos_intensity", 1.0))
	_chaos_duration_mult = float(cfg.get_value(CONFIG_SECTION, "chaos_duration_mult", 1.0))
	_chaos_particles = bool(cfg.get_value(CONFIG_SECTION, "chaos_particles", true))
	_chaos_auto_restore = bool(cfg.get_value(CONFIG_SECTION, "chaos_auto_restore", true))
	_chaos_shake = bool(cfg.get_value(CONFIG_SECTION, "chaos_shake", true))
	_chaos_emojis = bool(cfg.get_value(CONFIG_SECTION, "chaos_emojis", true))
	_chaos_on_success = bool(cfg.get_value(CONFIG_SECTION, "chaos_on_success", true))
	_crt_enabled = bool(cfg.get_value(CONFIG_SECTION, "crt_enabled", false))
	_crt_intensity = float(cfg.get_value(CONFIG_SECTION, "crt_intensity", 0.35))
	_crt_intensity = clampf(_crt_intensity, 0.05, 1.0)
	_neon_enabled = bool(cfg.get_value(CONFIG_SECTION, "neon_enabled", false))
	_predator_enabled = bool(cfg.get_value(CONFIG_SECTION, "predator_enabled", false))
	_predator_intensity = clampf(float(cfg.get_value(CONFIG_SECTION, "predator_intensity", 0.45)), 0.1, 1.0)
	_rain_enabled = bool(cfg.get_value(CONFIG_SECTION, "rain_enabled", false))
	_rain_intensity = clampf(float(cfg.get_value(CONFIG_SECTION, "rain_intensity", 0.5)), 0.1, 1.0)
	_paper_enabled = bool(cfg.get_value(CONFIG_SECTION, "paper_enabled", false))
	_paper_intensity = clampf(float(cfg.get_value(CONFIG_SECTION, "paper_intensity", 0.4)), 0.1, 1.0)
	_neon_intensity = clampf(float(cfg.get_value(CONFIG_SECTION, "neon_intensity", 0.7)), 0.1, 1.5)
	_crt_motion = bool(cfg.get_value(CONFIG_SECTION, "crt_motion", false))
	_arcade_copy = bool(cfg.get_value(CONFIG_SECTION, "arcade_copy", false))
	_sfx_enabled = bool(cfg.get_value(CONFIG_SECTION, "sfx_enabled", false))
	var hist_raw = cfg.get_value(CONFIG_SECTION, "deploy_history", [])
	_deploy_history.clear()
	if typeof(hist_raw) == TYPE_ARRAY:
		for e in hist_raw:
			if typeof(e) == TYPE_DICTIONARY:
				_deploy_history.append(e)
	_refresh_hist_list()


var _save_cfg_timer: Timer = null
var _save_cfg_pending: bool = false


func _save_config() -> void:
	## Debounce : regroupe les sauvegardes rapprochées (sliders, toggles) en une seule écriture disque.
	_save_cfg_pending = true
	if _save_cfg_timer == null:
		_save_cfg_timer = Timer.new()
		_save_cfg_timer.one_shot = true
		_save_cfg_timer.wait_time = 0.5
		_save_cfg_timer.timeout.connect(_flush_config)
		add_child(_save_cfg_timer)
	_save_cfg_timer.start()


func _flush_config() -> void:
	if not _save_cfg_pending:
		return
	_save_cfg_pending = false
	if not is_instance_valid(api_base_edit) or not is_instance_valid(email_edit):
		return
	_save_config_now()


func _exit_tree() -> void:
	# Ne pas perdre une sauvegarde en attente à la fermeture / désactivation du plugin
	_flush_config()


func _save_config_now() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # keep other keys
	cfg.set_value(CONFIG_SECTION, "api_base", api_base_edit.text.strip_edges())
	cfg.set_value(CONFIG_SECTION, "email", email_edit.text.strip_edges())
	# Ne JAMAIS écrire access_token / refresh_token en clair
	cfg.set_value(CONFIG_SECTION, "access_token", "")
	cfg.set_value(CONFIG_SECTION, "refresh_token", "")
	cfg.set_value(CONFIG_SECTION, "last_game_id", selected_game_id)
	if is_instance_valid(store_base_edit):
		cfg.set_value(CONFIG_SECTION, "store_base", store_base_edit.text.strip_edges())
	cfg.set_value(CONFIG_SECTION, "ship_total", _ship_total)
	cfg.set_value(CONFIG_SECTION, "ship_week_count", _ship_week_count)
	cfg.set_value(CONFIG_SECTION, "ship_week_key", _ship_week_key)
	cfg.set_value(CONFIG_SECTION, "ui_theme", _ui_theme)
	# Sérialise presets utilisateur (couleurs → html)
	var user_ser := {}
	for n in _user_themes.keys():
		user_ser[str(n)] = _theme_dict_to_json(_user_themes[n])
	cfg.set_value(CONFIG_SECTION, "user_themes_json", JSON.stringify(user_ser))
	cfg.set_value(CONFIG_SECTION, "music_path", _music_path)
	cfg.set_value(CONFIG_SECTION, "music_vol", _music_volume_db)
	cfg.set_value(CONFIG_SECTION, "music_loop", _music_loop)
	cfg.set_value(CONFIG_SECTION, "cozy_mode", _cozy_mode)
	cfg.set_value(CONFIG_SECTION, "festive_enabled", _festive_enabled)
	cfg.set_value(CONFIG_SECTION, "music_playlist", _music_playlist)
	cfg.set_value(CONFIG_SECTION, "music_pl_index", _music_pl_index)
	cfg.set_value(CONFIG_SECTION, "quote_day", _quote_shown_day)
	cfg.set_value(CONFIG_SECTION, "onboarding_done", _onboarding_done)
	cfg.set_value(CONFIG_SECTION, "chaos_intensity", _chaos_intensity)
	cfg.set_value(CONFIG_SECTION, "chaos_duration_mult", _chaos_duration_mult)
	cfg.set_value(CONFIG_SECTION, "chaos_particles", _chaos_particles)
	cfg.set_value(CONFIG_SECTION, "chaos_auto_restore", _chaos_auto_restore)
	cfg.set_value(CONFIG_SECTION, "chaos_shake", _chaos_shake)
	cfg.set_value(CONFIG_SECTION, "chaos_emojis", _chaos_emojis)
	cfg.set_value(CONFIG_SECTION, "chaos_on_success", _chaos_on_success)
	cfg.set_value(CONFIG_SECTION, "crt_enabled", _crt_enabled)
	cfg.set_value(CONFIG_SECTION, "crt_intensity", _crt_intensity)
	cfg.set_value(CONFIG_SECTION, "neon_enabled", _neon_enabled)
	cfg.set_value(CONFIG_SECTION, "neon_intensity", _neon_intensity)
	cfg.set_value(CONFIG_SECTION, "predator_enabled", _predator_enabled)
	cfg.set_value(CONFIG_SECTION, "predator_intensity", _predator_intensity)
	cfg.set_value(CONFIG_SECTION, "rain_enabled", _rain_enabled)
	cfg.set_value(CONFIG_SECTION, "rain_intensity", _rain_intensity)
	cfg.set_value(CONFIG_SECTION, "paper_enabled", _paper_enabled)
	cfg.set_value(CONFIG_SECTION, "paper_intensity", _paper_intensity)
	cfg.set_value(CONFIG_SECTION, "crt_motion", _crt_motion)
	cfg.set_value(CONFIG_SECTION, "arcade_copy", _arcade_copy)
	cfg.set_value(CONFIG_SECTION, "sfx_enabled", _sfx_enabled)
	cfg.set_value(CONFIG_SECTION, "deploy_history", _deploy_history)
	cfg.save(CONFIG_PATH)
	_save_secure_tokens()


func _api_base() -> String:
	var b := api_base_edit.text.strip_edges()
	# Garde uniquement la 1re « partie » (évite un texte collé après l'URL)
	if " " in b or "\t" in b or "\n" in b:
		b = b.split(" ")[0].split("\t")[0].split("\n")[0]
	# Schéma manquant → https
	if b != "" and not b.begins_with("http://") and not b.begins_with("https://"):
		b = "https://" + b
	# Faute de frappe connue (« ...storemet »)
	b = b.replace("thiossane.storemet", "thiossane.store")
	b = b.trim_suffix("/")
	# Backend de prod : les routes sont sous /api
	if b == "https://api.thiossane.store" or b == "http://api.thiossane.store":
		b += "/api"
	return b


func _auth_headers(include_bearer: bool = true) -> PackedStringArray:
	# Connection: close évite des soucis avec le serveur PHP intégré (keep-alive / Expect)
	var h: PackedStringArray = [
		"Content-Type: application/json",
		"Accept: application/json",
		"Connection: close",
	]
	# Ne JAMAIS envoyer un ancien JWT sur /login : SimpleJwtAuthenticator
	# intercepte Authorization et répond 401 avant d'atteindre AuthController.
	if include_bearer and access_token != "":
		h.append("Authorization: Bearer " + access_token)
		h.append("X-Access-Token: " + access_token)
	return h


# ══════════════════════════════════════════════════════════════════════════════
# LOGGING / FEEDBACK
# ══════════════════════════════════════════════════════════════════════════════

const LOG_MAX_LINES := 400
const LOG_TRIM_LINES := 100
var _log_line_count: int = 0


func _log(msg: String, level: String = "info") -> void:
	var ts := Time.get_time_string_from_system()
	var icon := {
		"ok": "✔",
		"err": "✖",
		"warn": "⚠",
		"info": "•",
		"busy": "…",
	}.get(level, "•")
	# Flavor sci-fi selon le thème actif
	var display := msg
	if _ui_theme == "matrix" and level in ["info", "busy", "ok"] and randf() < 0.35:
		display = _yautja_flavor(msg)
	elif _ui_theme == "matrix" and level == "ok" and randf() < 0.25:
		display = "› %s  // TERMINATED" % msg
	if is_instance_valid(log_edit):
		var t: String = log_edit.text + ("[%s] %s %s\n" % [ts, icon, display])
		_log_line_count += 1
		if _log_line_count > LOG_MAX_LINES:
			# Plafonne le journal : supprime les LOG_TRIM_LINES plus anciennes lignes
			var cut := 0
			for _i in LOG_TRIM_LINES:
				var nl := t.find("\n", cut)
				if nl < 0:
					break
				cut = nl + 1
			t = t.substr(cut)
			_log_line_count -= LOG_TRIM_LINES
		log_edit.text = t
		log_edit.scroll_vertical = log_edit.get_line_count()
	print("[Thiossane] ", msg)


## Langage Yautja (Predator) — approximation ludique + glitch Matrix.
## Transforme une partie du texte en glyphes angulaires et ajoute des clics.
func _yautja_flavor(src: String) -> String:
	const GLYPHS := "ꖌꖎꖒꖔꖕꖖꖗꖘꖙꖚꖛꖜꖝꖞꖟꖠꖡꖢꖣꖤꖥꖦꖧꖨꖩꖪꖫꖬꖭꖮꖯᚠᚡᚢᚣᚤᚥᚦᚧᚨᚩ"
	var out := ""
	var i := 0
	for ch in src:
		if ch == " " or ch == "." or ch == "," or ch == ":" or ch == "…" or ch == "—":
			out += ch
		elif randf() < 0.42:
			out += GLYPHS[hash(ch) % GLYPHS.length()]
		else:
			out += ch
		i += 1
		if i % 18 == 0 and randf() < 0.3:
			out += " *click*"
	# Préfixe / suffixe Predator occasionnel
	var prefixes := ["[YAUTJA] ", "⚔ HUNTER › ", "*click-click* ", "𐌈 SCAN › "]
	var suffixes := [" — prey acquired", " // heat signature OK", " *click*", " ⚔️"]
	if randf() < 0.55:
		out = prefixes[randi() % prefixes.size()] + out
	if randf() < 0.4:
		out += suffixes[randi() % suffixes.size()]
	return out


## Lignes Terminator / Matrix pour statut busy & célébrations.
func _scifi_status_line(kind: String = "busy") -> String:
	match kind:
		"busy":
			var lines_fr := [
				"CIBLE ACQUISE — analyse du build en cours…",
				"SYSTÈME EN LIGNE. Déploiement initié.",
				"Come with me if you want to ship.",
				"Mission : upload. Échec n’est pas une option.",
				"Scanner thermique… ZIP détecté.",
			]
			var lines_en := [
				"TARGET ACQUIRED — analyzing build…",
				"SYSTEM ONLINE. Deploy sequence initiated.",
				"Come with me if you want to ship.",
				"Mission: upload. Failure is not an option.",
				"Thermal scan… ZIP signature detected.",
			]
			var lines_zh := [
				"目标已锁定 — 正在分析构建…",
				"系统在线。部署序列已启动。",
				"跟我来如果你想 ship。",
				"任务：上传。失败不是选项。",
				"热扫描…检测到 ZIP 信号。",
			]
			var bag: Array = _mascot_lang_bag(lines_fr, lines_en, lines_zh)
			return bag[randi() % bag.size()]
		"ok":
			var lines_fr := [
				"TERMINATED. Build envoyé avec succès.",
				"I'll be back… pour le prochain patch.",
				"Hasta la vista, bugs.",
				"Mission accomplie. Retour à la base.",
			]
			var lines_en := [
				"TERMINATED. Build uploaded successfully.",
				"I'll be back… for the next patch.",
				"Hasta la vista, bugs.",
				"Mission complete. Returning to base.",
			]
			var lines_zh := [
				"TERMINATED. 构建已成功上传。",
				"I'll be back…带来下一个补丁。",
				"Hasta la vista，bugs。",
				"任务完成。返回基地。",
			]
			var bag: Array = _mascot_lang_bag(lines_fr, lines_en, lines_zh)
			return bag[randi() % bag.size()]
		"logout":
			return "I'll be back."
		_:
			return ""


func _set_step(text: String, pct: float = -1.0) -> void:
	if is_instance_valid(step_label):
		step_label.text = text
		step_label.modulate = C_BUSY if is_busy else C_INFO
	if pct >= 0.0 and is_instance_valid(progress_bar):
		progress_bar.value = pct
	_log(text, "busy" if is_busy else "info")


func _set_busy(busy: bool) -> void:
	is_busy = busy
	_update_queue_status_ui()
	if is_instance_valid(connect_btn):
		connect_btn.disabled = busy
	if is_instance_valid(create_game_btn):
		create_game_btn.disabled = busy
	if is_instance_valid(deploy_btn):
		deploy_btn.disabled = busy
		if busy:
			_set_deploy_ready_glow(false)
		elif not busy:
			_update_deploy_checklist()
	if is_instance_valid(resubmit_btn):
		resubmit_btn.disabled = busy
	if is_instance_valid(refresh_games_btn):
		refresh_games_btn.disabled = busy
	if busy:
		_chaos_hint_shown_this_busy = false
		if _ui_theme == "matrix":
			_feedback(_scifi_status_line("busy"), "busy")
		else:
			_feedback(tr_ui("busy"), "busy")
		_ensure_section_open(_sec_prog)
		_ensure_section_open(_sec_deploy)
		if is_instance_valid(_busy_tip_timer):
			_busy_tip_timer.start()
		if is_instance_valid(_tip_timer):
			_tip_timer.stop()
	else:
		if is_instance_valid(_busy_tip_timer):
			_busy_tip_timer.stop()
		if is_instance_valid(_tip_timer):
			_tip_timer.start()
		if is_instance_valid(progress_bar) and progress_bar.value >= 100.0:
			pass  # laisser le dernier feedback succès
		else:
			if access_token != "":
				_feedback(tr_ui("ready"), "idle")
			else:
				_feedback(tr_ui("login_to_start"), "idle")
			_comfort_refresh_greeting()


## Crée un bandeau de feedback local (près d'un bouton).
## Retourne [PanelContainer, Label].
func _make_local_feedback() -> Array:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BANNER_IDLE
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = C_BORDER
	panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", _ed_font())
	panel.add_child(lbl)
	return [panel, lbl]


func _style_feedback_panel(panel: PanelContainer, label: Label, msg: String, level: String) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(label):
		return
	label.text = msg
	panel.visible = true
	var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_color = C_BORDER
		panel.add_theme_stylebox_override("panel", sb)
	match level:
		"ok":
			sb.bg_color = C_BANNER_OK
			label.modulate = C_OK
		"err":
			sb.bg_color = C_BANNER_ERR
			label.modulate = C_ERR
		"warn":
			sb.bg_color = C_BANNER_WARN
			label.modulate = C_WARN
		"busy":
			sb.bg_color = C_BANNER_WARN
			label.modulate = C_BUSY
		"idle":
			sb.bg_color = C_BANNER_IDLE
			label.modulate = C_MUTED
		_:
			sb.bg_color = C_BANNER_INFO
			label.modulate = C_INFO


## Affiche le feedback près de la zone concernée (auth / fiche / deploy).
## zone optionnel : "auth" | "fiche" | "deploy" | "all" (défaut = dernière zone active).
func _feedback(msg: String, level: String = "info", zone: String = "") -> void:
	var z := zone if zone != "" else _fb_zone
	if z == "" or z == "all":
		# Messages globaux (session, idle) → bannière haute uniquement
		_style_feedback_panel(_status_banner, _status_banner_label, msg, level)
		# Masquer les slots locaux pour les messages idle globaux
		if level == "idle":
			if is_instance_valid(_fb_auth):
				_fb_auth.visible = false
			if is_instance_valid(_fb_fiche):
				_fb_fiche.visible = false
			if is_instance_valid(_fb_deploy):
				_fb_deploy.visible = false
		return

	# Feedback contextuel : uniquement sur le slot de la zone
	var panel: PanelContainer = null
	var label: Label = null
	match z:
		"auth":
			panel = _fb_auth
			label = _fb_auth_label
		"fiche":
			panel = _fb_fiche
			label = _fb_fiche_label
		"deploy":
			panel = _fb_deploy
			label = _fb_deploy_label
		_:
			panel = _status_banner
			label = _status_banner_label

	_style_feedback_panel(panel, label, msg, level)

	# Bannière haute : miroir discret pour erreurs/succès (sans remplacer le local)
	if level in ["ok", "err", "warn", "busy"] and is_instance_valid(_status_banner_label):
		_status_banner_label.text = msg
		if is_instance_valid(_status_banner):
			var sb := _status_banner.get_theme_stylebox("panel") as StyleBoxFlat
			if sb:
				match level:
					"ok":
						sb.bg_color = C_BANNER_OK
					"err":
						sb.bg_color = C_BANNER_ERR
					"warn", "busy":
						sb.bg_color = C_BANNER_WARN
					_:
						sb.bg_color = C_BANNER_INFO

	# Faire défiler jusqu'au message pour qu'il soit visible
	if is_instance_valid(panel) and panel.visible:
		call_deferred("_scroll_to_control", panel)

	if level == "ok" and is_instance_valid(_feedback_timer):
		_feedback_timer.stop()
		_feedback_timer.start(6.0)


var _scroll_tween: Tween

func _scroll_to_control(ctrl: Control) -> void:
	## Défilement fluide vers un contrôle (feedback, section…) — ease doux, pas de saut.
	if not is_instance_valid(_scroll) or not is_instance_valid(ctrl):
		return
	await get_tree().process_frame
	if not is_instance_valid(ctrl) or not is_instance_valid(_scroll):
		return
	# Laisser le layout se stabiliser (panel visible / taille finale)
	await get_tree().process_frame
	if not is_instance_valid(ctrl) or not is_instance_valid(_scroll):
		return

	var global_y := ctrl.global_position.y
	var scroll_y := _scroll.global_position.y
	var rel := global_y - scroll_y + float(_scroll.scroll_vertical)
	# Marge haute confortable pour ne pas coller le message en haut
	var target := maxf(rel - 36.0, 0.0)
	var current := float(_scroll.scroll_vertical)
	var delta := absf(target - current)
	# Déjà visible dans la zone utile → pas de scroll
	var view_h := _scroll.size.y
	var ctrl_top_in_view := global_y - scroll_y
	if ctrl_top_in_view >= 12.0 and ctrl_top_in_view + ctrl.size.y <= view_h - 8.0:
		return
	if delta < 4.0:
		return

	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.kill()
	# Durée proportionnelle à la distance, plafonnée (fluide sans être lent)
	var duration := clampf(0.22 + delta / 900.0, 0.28, 0.55)
	_scroll_tween = create_tween()
	_scroll_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_scroll_tween.tween_method(_set_scroll_vertical_smooth, current, target, duration)


func _set_scroll_vertical_smooth(value: float) -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(round(value))


func _on_feedback_timeout() -> void:
	if is_busy:
		return
	# Efface seulement le slot de la zone active ; idle global en haut
	if access_token != "":
		_feedback(tr_ui("ready"), "idle", "all")
	else:
		_feedback(tr_ui("login_to_start"), "idle", "all")


func _set_conn_state(connected: bool, detail: String = "") -> void:
	if is_instance_valid(_conn_dot):
		_set_conn_dot_color(C_OK if connected else C_ERR)
	if is_instance_valid(_conn_label):
		if connected:
			_conn_label.text = detail if detail != "" else tr_ui("connected")
			_conn_label.modulate = C_OK
		else:
			_conn_label.text = detail if detail != "" else tr_ui("not_connected")
			_conn_label.modulate = C_MUTED
	if is_instance_valid(user_label):
		if connected and detail != "":
			user_label.text = detail
			user_label.modulate = C_OK
			user_label.visible = true
		else:
			user_label.visible = false
			user_label.text = ""


func _style_primary_button(btn: Button) -> void:
	## Bouton primaire — couleurs + formes du thème actif
	if not is_instance_valid(btn):
		return
	btn.custom_minimum_size.y = 48
	btn.add_theme_font_size_override("font_size", _ed_font(_t_font_delta))
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PRIMARY
	normal.set_corner_radius_all(_t_radius_btn)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	normal.border_width_left = _t_border_w
	normal.border_width_right = _t_border_w
	normal.border_width_top = _t_border_w
	normal.border_width_bottom = _t_border_w
	normal.border_color = C_PRIMARY.lightened(0.12)
	normal.shadow_color = Color(C_PRIMARY.r, C_PRIMARY.g, C_PRIMARY.b, 0.28)
	normal.shadow_size = maxi(2, int(_t_shadow_size * 0.85))
	normal.shadow_offset = Vector2(0, 2)
	normal.anti_aliasing = true
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = C_PRIMARY.lightened(0.1)
	hover.border_color = C_PRIMARY.lightened(0.22)
	hover.shadow_color = Color(C_PRIMARY.r, C_PRIMARY.g, C_PRIMARY.b, 0.42)
	hover.shadow_size = maxi(4, int(_t_shadow_size * 1.3))
	hover.shadow_offset = Vector2(0, 3)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = C_PRIMARY.darkened(0.18)
	pressed.border_color = C_PRIMARY.darkened(0.25)
	pressed.shadow_size = 2
	pressed.shadow_offset = Vector2(0, 1)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = C_SURFACE
	disabled.border_color = C_BORDER
	disabled.shadow_size = 0
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_color", C_PRIMARY_FG)
	btn.add_theme_color_override("font_hover_color", C_PRIMARY_FG)
	btn.add_theme_color_override("font_pressed_color", C_PRIMARY_FG.darkened(0.1))
	btn.add_theme_color_override("font_disabled_color", C_MUTED)


func _style_success_button(btn: Button) -> void:
	## Bouton Launch — CTA principal selon le thème
	if not is_instance_valid(btn):
		return
	btn.custom_minimum_size.y = 54
	btn.add_theme_font_size_override("font_size", _ed_font(1 + _t_font_delta))
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PRIMARY
	normal.set_corner_radius_all(maxi(_t_radius_btn, _t_radius_card - 2))
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	normal.content_margin_top = 14
	normal.content_margin_bottom = 14
	normal.border_width_left = _t_border_w
	normal.border_width_right = _t_border_w
	normal.border_width_top = _t_border_w
	normal.border_width_bottom = _t_border_w
	normal.border_color = C_PRIMARY.lightened(0.15)
	normal.shadow_color = Color(C_PRIMARY.r, C_PRIMARY.g, C_PRIMARY.b, 0.38)
	normal.shadow_size = maxi(4, int(_t_shadow_size * 1.3))
	normal.shadow_offset = Vector2(0, 3)
	normal.anti_aliasing = true
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = C_PRIMARY.lightened(0.12)
	hover.border_color = C_PRIMARY.lightened(0.25)
	hover.shadow_color = Color(C_PRIMARY.r, C_PRIMARY.g, C_PRIMARY.b, 0.55)
	hover.shadow_size = maxi(6, int(_t_shadow_size * 1.8))
	hover.shadow_offset = Vector2(0, 4)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = C_PRIMARY.darkened(0.2)
	pressed.border_color = C_PRIMARY.darkened(0.28)
	pressed.shadow_size = 3
	pressed.shadow_offset = Vector2(0, 1)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = C_SURFACE
	disabled.border_color = C_BORDER
	disabled.shadow_size = 0
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_color", C_PRIMARY_FG)
	btn.add_theme_color_override("font_hover_color", C_PRIMARY_FG)
	btn.add_theme_color_override("font_pressed_color", C_PRIMARY_FG.darkened(0.1))
	btn.add_theme_color_override("font_disabled_color", C_MUTED)


func _style_secondary_button(btn: Button) -> void:
	## Bouton secondaire : surface glass-like, bordure fine, hover or
	if not is_instance_valid(btn):
		return
	btn.add_theme_font_size_override("font_size", _ed_font())
	btn.custom_minimum_size.y = 42
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(C_SURFACE.r, C_SURFACE.g, C_SURFACE.b, 0.92)
	normal.set_corner_radius_all(11)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.border_color = C_BORDER
	normal.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	normal.shadow_size = 3
	normal.shadow_offset = Vector2(0, 1)
	normal.anti_aliasing = true
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = C_HOVER_SURFACE
	hover.border_color = C_PRIMARY
	hover.shadow_color = Color(0.91, 0.73, 0.29, 0.22)
	hover.shadow_size = 6
	hover.shadow_offset = Vector2(0, 2)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = C_PRESSED_SURFACE
	pressed.border_color = C_PRIMARY.darkened(0.15)
	pressed.shadow_size = 1
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_color_override("font_hover_color", C_PRIMARY)
	btn.add_theme_color_override("font_pressed_color", C_PRIMARY.lightened(0.15))


# ══════════════════════════════════════════════════════════════════════════════
# PRESETS
# ══════════════════════════════════════════════════════════════════════════════

func _refresh_presets() -> void:
	preset_web.clear()
	preset_windows.clear()
	preset_android.clear()
	preset_web.add_item("— Choisir un preset —", -1)
	preset_windows.add_item("— Choisir un preset —", -1)
	preset_android.add_item("— Choisir un preset —", -1)

	# Liste des presets via export_presets.cfg (EditorExport en @tool)
	var export_presets_path := "res://export_presets.cfg"
	var cfg := ConfigFile.new()
	if cfg.load(export_presets_path) != OK:
		_log("Aucun export_presets.cfg trouvé. Créez des presets via Projet → Exporter…")
		return

	var preset_count := 0
	while cfg.has_section("preset.%d" % preset_count):
		var name: String = str(cfg.get_value("preset.%d" % preset_count, "name", "Preset %d" % preset_count))
		var platform: String = str(cfg.get_value("preset.%d" % preset_count, "platform", "")).to_lower()
		var runnable: bool = bool(cfg.get_value("preset.%d" % preset_count, "runnable", true))

		if "web" in platform or "html" in platform:
			preset_web.add_item(name, preset_count)
		elif "windows" in platform or "pc" in platform or "desktop" in platform:
			preset_windows.add_item(name, preset_count)
		elif "android" in platform:
			preset_android.add_item(name, preset_count)
		else:
			# fallback: propose everywhere
			preset_web.add_item(name + " (?)", preset_count)
			preset_windows.add_item(name + " (?)", preset_count)
			preset_android.add_item(name + " (?)", preset_count)
		preset_count += 1

	_log("%d preset(s) d'export détecté(s)." % preset_count)


# ══════════════════════════════════════════════════════════════════════════════
# HTTP helpers
# ══════════════════════════════════════════════════════════════════════════════

enum ReqKind { NONE, LOGIN, ME, CATEGORIES, MY_GAMES, CREATE_GAME, UPDATE_GAME, RESUBMIT, REFRESH, SHARE_LINK, SHARE_STATS, MKT_ANALYTICS, AMBASSADOR_CREATE, AMBASSADOR_LIST, AMBASSADOR_STATS, AMBASSADOR_REVOKE, UPLOAD_INIT, UPLOAD_STATUS, UPLOAD_COMPLETE, SUPPORT_CREATE, SUPPORT_LIST, SUPPORT_GET, SUPPORT_REPLY, NOTIF_LIST, NOTIF_MARK_ALL, GENERIC }
var _pending_kind: ReqKind = ReqKind.NONE
var _pending_callback: Callable = Callable()


func _http_result_name(result: int) -> String:
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


## Extrait une liste d'une réponse API (Pagination items, Hydra, tableau brut).
func _extract_collection(data: Variant) -> Array:
	if typeof(data) == TYPE_ARRAY:
		return data
	if typeof(data) != TYPE_DICTIONARY:
		return []
	var d: Dictionary = data
	for key in ["items", "hydra:member", "member", "data", "results", "games", "categories"]:
		if not d.has(key):
			continue
		var v = d[key]
		if typeof(v) == TYPE_ARRAY:
			return v
		if typeof(v) == TYPE_DICTIONARY:
			for k2 in ["items", "hydra:member", "member"]:
				if v.has(k2) and typeof(v[k2]) == TYPE_ARRAY:
					return v[k2]
	return []


func _request_json(method: int, path: String, body: Dictionary = {}, kind: ReqKind = ReqKind.GENERIC, cb: Callable = Callable()) -> void:
	if not is_instance_valid(http) or not http.is_inside_tree():
		_log("HTTPRequest non prêt (pas dans l'arbre de scène).")
		_set_busy(false)
		return

	# Une seule requête à la fois : annuler l'éventuelle requête en cours
	http.cancel_request()

	_pending_kind = kind
	_pending_callback = cb
	var url := _api_base() + path
	# Login sans Bearer : un token périmé ferait échouer l'authenticator (401 signature/exp)
	var headers := _auth_headers(kind != ReqKind.LOGIN)
	var payload := ""
	if method != HTTPClient.METHOD_GET and not body.is_empty():
		payload = JSON.stringify(body)

	var method_name := {
		HTTPClient.METHOD_GET: "GET",
		HTTPClient.METHOD_POST: "POST",
		HTTPClient.METHOD_PUT: "PUT",
		HTTPClient.METHOD_DELETE: "DELETE",
		HTTPClient.METHOD_PATCH: "PATCH",
	}.get(method, str(method))
	_log("→ %s %s (%d octets)" % [method_name, url, payload.length()])

	var err := http.request(url, headers, method, payload)
	if err != OK:
		_log("Erreur HTTPRequest.request(): %s" % error_string(err))
		_set_busy(false)
		_pending_kind = ReqKind.NONE
		_feedback("Erreur HTTPRequest : %s" % error_string(err), "err")


func _on_http_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var kind := _pending_kind
	var cb := _pending_callback
	_pending_kind = ReqKind.NONE
	_pending_callback = Callable()

	var text := body.get_string_from_utf8()
	var data: Variant = null
	if text.strip_edges() != "":
		var json := JSON.new()
		if json.parse(text) == OK:
			data = json.get_data()

	if result != HTTPRequest.RESULT_SUCCESS:
		var rname := _http_result_name(result)
		var human := _human_network_error(result)
		_log(human, "err")
		print("[Thiossane] network detail result=%d (%s) HTTP=%d URL=%s" % [result, rname, response_code, _api_base()])
		_set_busy(false)
		_feedback(human, "err")
		return

	# Auto-refresh sur 401 (sauf login / refresh eux-mêmes)
	if response_code == 401 and kind != ReqKind.LOGIN and kind != ReqKind.REFRESH:
		if refresh_token != "" and not _refreshing_token:
			_log("Token expiré (401) — tentative de refresh…")
			_retry_after_refresh = {"kind": kind}
			_try_refresh_token()
			return
		_log(tr_ui("session_expired"), "err")
		_feedback(tr_ui("session_expired"), "err")
		access_token = ""
		_save_config()
		_set_busy(false)
		user_label.text = tr_ui("not_connected")
		return

	match kind:
		ReqKind.LOGIN:
			_handle_login(response_code, data)
		ReqKind.ME:
			_handle_me(response_code, data)
		ReqKind.CATEGORIES:
			_handle_categories(response_code, data)
		ReqKind.MY_GAMES:
			_handle_my_games(response_code, data)
		ReqKind.CREATE_GAME, ReqKind.UPDATE_GAME:
			_handle_create_game(response_code, data, kind == ReqKind.UPDATE_GAME)
		ReqKind.RESUBMIT:
			_handle_resubmit(response_code, data)
		ReqKind.REFRESH:
			_handle_refresh(response_code, data)
		ReqKind.SHARE_LINK:
			_handle_share_link(response_code, data)
		ReqKind.SHARE_STATS:
			_handle_share_stats(response_code, data)
		ReqKind.AMBASSADOR_CREATE:
			_handle_ambassador_create(response_code, data)
		ReqKind.AMBASSADOR_LIST:
			_handle_ambassador_list(response_code, data)
		ReqKind.AMBASSADOR_STATS:
			_handle_ambassador_stats(response_code, data)
		ReqKind.AMBASSADOR_REVOKE:
			_handle_ambassador_revoke(response_code, data)
		ReqKind.MKT_ANALYTICS:
			_handle_mkt_analytics(response_code, data)
		ReqKind.UPLOAD_INIT:
			_handle_upload_init(response_code, data)
		ReqKind.UPLOAD_STATUS:
			_handle_upload_status(response_code, data)
		ReqKind.UPLOAD_COMPLETE:
			_handle_upload_complete(response_code, data)
		ReqKind.SUPPORT_CREATE:
			_handle_support_create(response_code, data)
		ReqKind.SUPPORT_LIST:
			_handle_support_list(response_code, data)
		ReqKind.SUPPORT_GET:
			_handle_support_get(response_code, data)
		ReqKind.SUPPORT_REPLY:
			_handle_support_reply(response_code, data)
		ReqKind.NOTIF_LIST:
			_handle_notif_list(response_code, data)
		ReqKind.NOTIF_MARK_ALL:
			_handle_notif_mark_all(response_code, data)
		_:
			if cb.is_valid():
				cb.call(response_code, data)
			else:
				_log("Réponse %d: %s" % [response_code, str(data).left(200)])
			_set_busy(false)


func _api_error_message(data: Variant, code: int) -> String:
	## Message humain + nuance « ce n’est pas toi » pour les erreurs serveur / réseau.
	var raw := ""
	if typeof(data) == TYPE_DICTIONARY:
		var d: Dictionary = data
		if d.has("message"):
			raw = str(d["message"])
		elif d.has("detail"):
			raw = str(d["detail"])
		elif d.has("hydra:description"):
			raw = str(d["hydra:description"])
		elif d.has("violations") and typeof(d["violations"]) == TYPE_ARRAY and d["violations"].size() > 0:
			var v = d["violations"][0]
			if typeof(v) == TYPE_DICTIONARY:
				raw = "%s: %s" % [str(v.get("propertyPath", "")), str(v.get("message", ""))]
	if code >= 500:
		var base := tr_ui("err_server_5xx") % code
		return base if raw == "" else "%s — %s" % [base, raw]
	if code == 401:
		return tr_ui("err_auth") if raw == "" else "%s (%s)" % [tr_ui("err_auth"), raw]
	if code == 403:
		return tr_ui("err_forbidden") if raw == "" else "%s (%s)" % [tr_ui("err_forbidden"), raw]
	if code == 404:
		return tr_ui("err_not_found") if raw == "" else "%s (%s)" % [tr_ui("err_not_found"), raw]
	if raw != "":
		return raw
	if code > 0:
		return tr_ui("err_generic") % code
	return tr_ui("err_not_you")


func _human_network_error(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "%s %s" % [tr_ui("err_cant_connect"), tr_ui("err_not_you")]
		HTTPRequest.RESULT_CANT_RESOLVE:
			return tr_ui("err_dns")
		HTTPRequest.RESULT_TIMEOUT:
			return "%s %s" % [tr_ui("err_timeout"), tr_ui("err_not_you")]
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return tr_ui("err_tls")
		HTTPRequest.RESULT_NO_RESPONSE:
			return tr_ui("err_no_response")
		_:
			return "%s (%s)" % [tr_ui("err_not_you"), _http_result_name(result)]


func _try_refresh_token() -> void:
	if refresh_token == "":
		_log("Pas de refresh_token disponible.")
		_set_busy(false)
		return
	_refreshing_token = true
	# Body JSON attendu par RefreshTokenController
	_request_json(HTTPClient.METHOD_POST, "/token/refresh", {
		"refresh_token": refresh_token,
	}, ReqKind.REFRESH)


func _handle_refresh(code: int, data: Variant) -> void:
	_refreshing_token = false
	if code < 200 or code >= 300 or typeof(data) != TYPE_DICTIONARY:
		_log("Refresh échoué HTTP %d: %s" % [code, _api_error_message(data, code)])
		_feedback(tr_ui("session_expired"), "err")
		access_token = ""
		refresh_token = ""
		_save_config()
		_set_busy(false)
		user_label.text = tr_ui("not_connected")
		_retry_after_refresh.clear()
		return

	var d: Dictionary = data
	var new_token := str(d.get("token", d.get("access_token", "")))
	if new_token == "":
		_log("Refresh OK mais token manquant.")
		_set_busy(false)
		return
	access_token = new_token
	var new_rt := str(d.get("refresh_token", d.get("refreshToken", "")))
	if new_rt != "":
		refresh_token = new_rt
	_save_config()
	_log("Token rafraîchi.")
	var retry := _retry_after_refresh.duplicate()
	_retry_after_refresh.clear()
	# Reprise upload en cours (chunk) après 401
	if str(retry.get("kind", "")) == "upload_chunk":
		_log(tr_ui("upload_resume_after_refresh"))
		_send_next_chunk()
		return
	# Sinon rejouer le flux post-auth
	_request_me()


# ══════════════════════════════════════════════════════════════════════════════
# AUTH
# ══════════════════════════════════════════════════════════════════════════════

func _on_connect_pressed() -> void:
	if is_busy:
		return
	_fb_zone = "auth"
	var email := email_edit.text.strip_edges()
	var password := password_edit.text
	if email == "" or password == "":
		_feedback(tr_ui("email_required"), "warn", "auth")
		return
	# Purge tokens locaux avant login (évite 401 signature/exp sur ancien JWT)
	access_token = ""
	refresh_token = ""
	_save_config()
	_set_busy(true)
	_set_step("Connexion en cours…", 10)
	_request_json(HTTPClient.METHOD_POST, "/login", {
		"email": email,
		"password": password,
	}, ReqKind.LOGIN)


func _handle_login(code: int, data: Variant) -> void:
	if code < 200 or code >= 300 or typeof(data) != TYPE_DICTIONARY:
		var detail := _api_error_message(data, code) if data != null else str(data)
		_log(tr_ui("login_fail") if detail == "" else detail, "err")
		print("[Thiossane] login HTTP %d: %s" % [code, detail if detail else str(data)])
		# Message plus clair si le serveur a vu un vieux JWT
		var raw := str(data).to_lower()
		if "jwt" in raw or "signature" in raw or "token" in raw:
			_feedback("Token JWT rejeté — reconnectez-vous (identifiants). Si ça persiste: mauvais JWT_SECRET côté serveur.", "err", "auth")
		else:
			_feedback(tr_ui("login_fail"), "err", "auth")
		_set_busy(false)
		return

	var d: Dictionary = data
	access_token = str(d.get("token", d.get("access_token", "")))
	if access_token == "" and d.has("data"):
		var inner = d["data"]
		if typeof(inner) == TYPE_DICTIONARY:
			access_token = str(inner.get("token", inner.get("access_token", "")))
	refresh_token = str(d.get("refresh_token", d.get("refreshToken", "")))

	if access_token == "":
		_log("Login OK mais pas de token dans la réponse.")
		_feedback("Réponse login invalide (token manquant).", "err")
		_set_busy(false)
		return

	# Profil déjà présent dans la réponse login
	var name_str := "Développeur"
	var role := ""
	if d.has("user") and typeof(d["user"]) == TYPE_DICTIONARY:
		current_user = d["user"]
		name_str = str(current_user.get("username", current_user.get("email", "Développeur")))
		role = str(current_user.get("role", ""))
		_set_conn_state(true, "Connecté : %s (%s)" % [name_str, role])
	_feedback(tr_ui("login_ok") % name_str, "ok")
	_workflow_fx("login")
	_comfort_on_success()
	if role != "" and "DEVELOPER" not in role.to_upper() and "ADMIN" not in role.to_upper():
		_log("Attention : rôle « %s » — ROLE_DEVELOPER recommandé pour déployer." % role, "warn")
		_feedback(tr_ui("role_warn") % role, "warn")

	_save_config()
	_log("Connecté. Token reçu.")
	_set_step("Récupération du profil…", 30)
	_request_me()


func _request_me() -> void:
	# Backend: GET /api/account
	_request_json(HTTPClient.METHOD_GET, "/account", {}, ReqKind.ME)


func _handle_me(code: int, data: Variant) -> void:
	if code < 200 or code >= 300:
		# still try to continue with token
		_log("Profil non récupéré (HTTP %d). On continue avec le token." % code, "warn")
		_set_conn_state(true, "Connecté (profil indisponible)")
		_feedback("Token OK, profil indisponible (HTTP %d)." % code, "warn")
		_after_auth()
		return

	if typeof(data) == TYPE_DICTIONARY:
		current_user = data
		var name_str := str(data.get("username", data.get("email", "Développeur")))
		var role := str(data.get("role", data.get("roles", "")))
		_set_conn_state(true, "Connecté : %s (%s)" % [name_str, role])
		_log("Profil OK : %s" % name_str, "ok")
	else:
		_set_conn_state(true, "Connecté (profil partiel)")
	_after_auth()


func _after_auth() -> void:
	_refresh_onboarding()
	_set_step(tr_ui("cats_loading_step"), 50)
	_log(tr_ui("cats_loading_step"), "busy")
	# Un seul HTTPRequest : ne PAS lancer notifications en parallèle
	# (sinon cancel_request() annule /categories et les jeux ne chargent jamais).
	_request_json(HTTPClient.METHOD_GET, "/categories", {}, ReqKind.CATEGORIES)


func _on_logout_pressed() -> void:
	_fb_zone = "auth"
	_clear_secure_tokens()
	current_user = {}
	my_games.clear()
	selected_game_id = -1
	_set_conn_state(false, tr_ui("not_connected"))
	game_option.clear()
	_save_config()
	_log(tr_ui("logout_ok"), "info")
	progress_bar.value = 0
	step_label.text = tr_ui("step_idle")
	step_label.modulate = C_MUTED
	_feedback(tr_ui("logout_ok"), "idle", "auth")


# ══════════════════════════════════════════════════════════════════════════════
# CATEGORIES & GAMES
# ══════════════════════════════════════════════════════════════════════════════

func _handle_categories(code: int, data: Variant) -> void:
	categories.clear()
	category_option.clear()
	category_option.add_item("— Choisir une catégorie —", -1)

	if code < 200 or code >= 300:
		_log("Catégories HTTP %d: %s" % [code, _api_error_message(data, code)], "warn")
		# On continue quand même vers les jeux
	else:
		var list: Array = _extract_collection(data)
		for c in list:
			if typeof(c) != TYPE_DICTIONARY:
				continue
			var id: int = int(c.get("id", -1))
			var name: String = str(c.get("name", "Catégorie %d" % id))
			if id >= 0:
				categories.append(c)
				category_option.add_item(name, id)

	_log(tr_ui("cats_found") % categories.size(), "ok" if categories.size() > 0 else "info")
	_set_step(tr_ui("games_loading_step"), 70)
	_request_my_games()


func _request_my_games() -> void:
	# Prefer dedicated endpoint
	_my_games_tried_fallback = false
	_show_games_loading(true)
	_request_json(HTTPClient.METHOD_GET, "/developer/my-games", {}, ReqKind.MY_GAMES)


func _show_games_loading(loading: bool) -> void:
	## Feedback local visible dans la section Jeu (pas seulement la barre Progression).
	if is_instance_valid(game_option):
		game_option.disabled = loading
		if loading:
			game_option.clear()
			game_option.add_item(tr_ui("games_loading"), -2)
			game_option.select(0)
	if is_instance_valid(refresh_games_btn):
		refresh_games_btn.disabled = loading
	if is_instance_valid(_game_empty_label):
		if loading:
			_game_empty_label.text = tr_ui("games_loading_hint")
			_game_empty_label.modulate = C_BUSY
			_game_empty_label.visible = true
		else:
			_game_empty_label.modulate = C_MUTED
			_game_empty_label.text = tr_ui("ob_game_empty")
	_set_step(tr_ui("games_loading_step"), 70 if loading else -1.0)
	_log(tr_ui("games_loading_step") if loading else "", "busy" if loading else "info")


func _handle_my_games(code: int, data: Variant) -> void:
	if code < 200 or code >= 300:
		# Un seul fallback pour éviter une boucle infinie
		if not _my_games_tried_fallback:
			_my_games_tried_fallback = true
			_log("my-games HTTP %d — tentative fallback /developer/games." % code)
			_request_json(HTTPClient.METHOD_GET, "/developer/games", {}, ReqKind.MY_GAMES)
			return
		_log("Impossible de charger les jeux (HTTP %d)." % code)
		_show_games_loading(false)
		if is_instance_valid(game_option):
			game_option.clear()
			game_option.add_item(tr_ui("new_game"), -1)
			game_option.disabled = false
		if is_instance_valid(_game_empty_label):
			_game_empty_label.text = tr_ui("games_load_fail") % code
			_game_empty_label.modulate = C_WARN
			_game_empty_label.visible = true
		_set_busy(false)
		_set_step(tr_ui("games_load_fail_step"), 100)
		_feedback(tr_ui("games_load_fail") % code, "warn")
		call_deferred("_on_notif_refresh")
		return

	_my_games_tried_fallback = false
	_show_games_loading(false)
	my_games.clear()
	game_option.clear()
	game_option.add_item(tr_ui("new_game"), -1)
	if is_instance_valid(game_option):
		game_option.disabled = false

	var list: Array = _extract_collection(data)

	var select_idx := 0
	for i in list.size():
		var g = list[i]
		if typeof(g) != TYPE_DICTIONARY:
			continue
		my_games.append(g)
		var gid: int = int(g.get("id", -1))
		var title: String = str(g.get("title", "Jeu %d" % gid))
		var status: String = str(g.get("status", ""))
		game_option.add_item("%s [%s]" % [title, status], gid)
		if gid == selected_game_id:
			select_idx = i + 1  # +1 because of "Nouveau jeu"

	if select_idx > 0:
		game_option.select(select_idx)
		_on_game_selected(select_idx)

	_log(tr_ui("games_found") % my_games.size(), "ok")
	_set_step(tr_ui("games_ready_step") % my_games.size(), 100)
	_set_busy(false)
	_fb_zone = "auth"
	if my_games.is_empty():
		_feedback(tr_ui("games_none"), "info", "auth")
	else:
		_feedback(tr_ui("games_found_fb") % my_games.size(), "ok", "auth")
	progress_bar.value = 100
	if is_instance_valid(game_option):
		game_option.disabled = false
	if is_instance_valid(refresh_games_btn):
		refresh_games_btn.disabled = false
	if is_instance_valid(_game_empty_label):
		_game_empty_label.text = tr_ui("ob_game_empty")
		_game_empty_label.modulate = C_MUTED
		_game_empty_label.visible = my_games.is_empty()
	_refresh_onboarding()
	# Notifications après la chaîne auth→cats→games (évite d’annuler my-games)
	call_deferred("_on_notif_refresh")


func _on_refresh_games() -> void:
	_fb_zone = "auth"
	if access_token == "":
		_feedback(tr_ui("connect_first"), "warn", "auth")
		return
	_set_busy(true)
	if is_instance_valid(_sec_game):
		_ensure_section_open(_sec_game)
	_feedback(tr_ui("games_loading_hint"), "busy", "auth")
	_request_my_games()


func _on_game_selected(idx: int) -> void:
	var id: int = game_option.get_item_id(idx)
	selected_game_id = id
	selected_game_status = "draft"
	if id < 0:
		# nouveau
		title_edit.text = ""
		desc_edit.text = ""
		price_edit.value = 0
		free_check.button_pressed = false
		demo_check.button_pressed = false
		browser_check.button_pressed = false
		release_edit.text = ""
		cover_edit.text = ""
		version_edit.text = "1.0.0"
		_clear_share_ui()
		_refresh_game_status_ui()
		_update_deploy_checklist()
		return

	for g in my_games:
		if int(g.get("id", -1)) == id:
			title_edit.text = str(g.get("title", ""))
			desc_edit.text = str(g.get("description", ""))
			price_edit.value = float(g.get("price", 0))
			free_check.button_pressed = bool(g.get("isFree", g.get("is_free", false)))
			demo_check.button_pressed = bool(g.get("hasDemo", g.get("has_demo", false)))
			browser_check.button_pressed = bool(g.get("playInBrowser", g.get("play_in_browser", false)))
			var rd = g.get("releaseDate", g.get("release_date", ""))
			release_edit.text = str(rd).substr(0, 10) if rd else ""
			cover_edit.text = str(g.get("coverImage", g.get("cover_image", "")))
			selected_game_status = str(g.get("status", "draft"))
			var cat = g.get("category", {})
			if typeof(cat) == TYPE_DICTIONARY:
				var cid: int = int(cat.get("id", -1))
				for i in category_option.item_count:
					if category_option.get_item_id(i) == cid:
						category_option.select(i)
						break
			break
	_clear_share_ui()
	_save_config()
	_refresh_game_status_ui()
	_update_deploy_checklist()


# ══════════════════════════════════════════════════════════════════════════════
# CREATE / UPDATE GAME
# ══════════════════════════════════════════════════════════════════════════════

func _on_create_game_pressed() -> void:
	if is_busy:
		return
	_fb_zone = "fiche"
	if access_token == "":
		_feedback(tr_ui("connect_first"), "warn", "fiche")
		return
	var title := title_edit.text.strip_edges()
	if title == "":
		_feedback(tr_ui("title_required"), "warn", "fiche")
		return
	var cat_id: int = category_option.get_selected_id()
	if cat_id < 0:
		_feedback(tr_ui("cat_required"), "warn", "fiche")
		return

	var is_free: bool = free_check.button_pressed
	var price_val: String = "0.00" if is_free else "%.2f" % price_edit.value

	# Ne pas envoyer de null (certains backends Symfony/API Platform les rejettent)
	var payload := {
		"title": title,
		"category": "/api/categories/%d" % cat_id,
		"price": price_val,
		"isFree": is_free,
		"hasDemo": demo_check.button_pressed,
		"playInBrowser": browser_check.button_pressed,
	}
	var desc_txt := desc_edit.text.strip_edges()
	if desc_txt != "":
		payload["description"] = desc_txt
	var rel_txt := release_edit.text.strip_edges()
	if rel_txt != "":
		payload["releaseDate"] = rel_txt
	var cover_txt := cover_edit.text.strip_edges()
	if cover_txt != "":
		payload["coverImage"] = cover_txt

	_set_busy(true)
	if selected_game_id > 0:
		# PUT = remplacement : sans "status", le backend applique le défaut
		# "draft" → securityPostDenormalize refuse (403). On renvoie le
		# statut courant ; GameUpdateProcessor passera approved → pending.
		var st := selected_game_status if selected_game_status != "" else "draft"
		payload["status"] = st
		_set_step("Mise à jour de la fiche…", 20)
		_request_json(HTTPClient.METHOD_PUT, "/games/%d" % selected_game_id, payload, ReqKind.UPDATE_GAME)
	else:
		_set_step("Création de la fiche (brouillon)…", 20)
		_request_json(HTTPClient.METHOD_POST, "/games", payload, ReqKind.CREATE_GAME)


func _handle_create_game(code: int, data: Variant, is_update: bool) -> void:
	if code < 200 or code >= 300:
		var msg := _api_error_message(data, code)
		_log("Erreur création/màj HTTP %d: %s" % [code, msg])
		_feedback(tr_ui("fiche_fail") % msg, "err")
		_set_busy(false)
		return

	var gid := selected_game_id
	if typeof(data) == TYPE_DICTIONARY:
		gid = int(data.get("id", gid))
		selected_game_id = gid
		_log("Fiche jeu enregistrée — id=%d" % gid)
		_feedback(tr_ui("fiche_ok") % gid, "ok")
		_workflow_fx("fiche")
	_save_config()
	_set_step("Fiche OK. Rafraîchissement…", 80)
	_request_my_games()


# ══════════════════════════════════════════════════════════════════════════════
# BIEN-ÊTRE WORKFLOW — statut explicite, checklist, redeploy
# ══════════════════════════════════════════════════════════════════════════════

func _refresh_game_status_ui() -> void:
	if not is_instance_valid(game_status_label):
		return
	if selected_game_id < 1:
		game_status_label.text = tr_ui("status_new")
		game_status_label.modulate = C_MUTED
		return
	var st := selected_game_status.to_lower().strip_edges()
	var note := ""
	for g in my_games:
		if int(g.get("id", -1)) == selected_game_id:
			note = str(g.get("moderationNote", g.get("moderation_note", ""))).strip_edges()
			break
	var line := ""
	var col := C_MUTED
	match st:
		"draft":
			line = "📝 " + tr_ui("status_draft")
			col = C_MUTED
		"pending":
			line = "⏳ " + tr_ui("status_pending")
			col = C_WARN
		"approved":
			line = "✅ " + tr_ui("status_approved")
			col = C_OK
		"rejected":
			line = "❌ " + tr_ui("status_rejected")
			col = C_ERR
		"suspended":
			line = "🚫 " + tr_ui("status_suspended")
			col = C_ERR
		_:
			line = tr_ui("status_unknown") % st
			col = C_MUTED
	if note != "":
		line += "\n💬 " + tr_ui("status_mod_note") + " " + note
	game_status_label.text = line
	game_status_label.modulate = col


func _update_deploy_checklist() -> void:
	if not is_instance_valid(deploy_checklist_label):
		return
	var issues := _preflight_issues()
	if issues.is_empty():
		deploy_checklist_label.text = "✔ " + tr_ui("checklist_ok")
		deploy_checklist_label.modulate = C_OK
		_set_deploy_ready_glow(true)
		if is_instance_valid(_preflight_panel):
			_preflight_panel.visible = false
	else:
		deploy_checklist_label.text = tr_ui("checklist_missing") % ", ".join(issues)
		deploy_checklist_label.modulate = C_WARN
		_set_deploy_ready_glow(false)
	_refresh_onboarding()


## Preflight bloquant — retourne la liste des problèmes (vide = OK).
## v1.9.38 : messages actionnables + contrôle presets / export_presets.cfg.
func _preflight_issues() -> PackedStringArray:
	var missing: PackedStringArray = []
	if access_token == "":
		missing.append(tr_ui("check_auth_hint"))
	if selected_game_id < 1:
		missing.append(tr_ui("check_game_hint"))
	if title_edit and title_edit.text.strip_edges() == "":
		missing.append(tr_ui("check_title_hint"))
	var ver := version_edit.text.strip_edges() if is_instance_valid(version_edit) else ""
	if ver == "":
		missing.append(tr_ui("check_version_hint"))
	elif not _version_looks_valid(ver):
		missing.append(tr_ui("check_version_fmt_hint"))

	var presets := _DeployCore.list_export_presets()
	if presets.is_empty():
		missing.append(tr_ui("check_no_presets_file"))

	var any_plat := false
	var checks := [
		{"on": is_instance_valid(platform_web) and platform_web.button_pressed, "key": "web", "opt": preset_web, "label": "Web"},
		{"on": is_instance_valid(platform_windows) and platform_windows.button_pressed, "key": "windows", "opt": preset_windows, "label": "Windows"},
		{"on": is_instance_valid(platform_android) and platform_android.button_pressed, "key": "android", "opt": preset_android, "label": "Android"},
	]
	for c in checks:
		if not c["on"]:
			continue
		any_plat = true
		var opt: OptionButton = c["opt"]
		if not is_instance_valid(opt) or opt.get_selected_id() < 0 or str(opt.get_item_text(opt.selected)).begins_with("—"):
			missing.append(tr_ui("check_preset_plat") % c["label"])
			continue
		var pname := str(opt.get_item_text(opt.selected))
		if pname.ends_with(" (?)"):
			pname = pname.substr(0, pname.length() - 4)
		var found := false
		var plat_ok := false
		for p in presets:
			if str(p.get("name", "")) == pname:
				found = true
				plat_ok = _DeployCore.platform_matches_preset(str(c["key"]), str(p.get("platform", "")))
				break
		if not found and not presets.is_empty():
			missing.append(tr_ui("check_preset_missing") % [pname, c["label"]])
		elif found and not plat_ok:
			missing.append(tr_ui("check_preset_mismatch") % [pname, c["label"]])

	if not any_plat:
		missing.append(tr_ui("check_plat_hint"))

	missing.append_array(_preflight_size_hints())
	return missing


func _version_looks_valid(v: String) -> bool:
	# Accepte 1.0.0, 1.0, 2, 1.2.3-beta — refuse chaînes vides ou purement textuelles
	var s := v.strip_edges()
	if s.length() < 1 or s.length() > 32:
		return false
	return s[0].is_valid_int() or s.begins_with("v")


func _preflight_size_hints() -> PackedStringArray:
	## Hint non bloquant sur la limite max (bloquant = après ZIP).
	return PackedStringArray()


func _show_preflight_block(issues: PackedStringArray) -> void:
	if is_instance_valid(_preflight_panel) and is_instance_valid(_preflight_label):
		var lines := tr_ui("preflight_title") + "\n"
		for i in issues:
			lines += "• " + i + "\n"
		_preflight_label.text = lines.strip_edges()
		_preflight_panel.visible = true
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(C_ERR.r * 0.35, C_ERR.g * 0.12, C_ERR.b * 0.12, 0.92)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_color = C_ERR
		_preflight_panel.add_theme_stylebox_override("panel", sb)
	_feedback(tr_ui("preflight_blocked"), "warn", "deploy")
	_log(tr_ui("preflight_blocked") + " — " + ", ".join(issues), "warn")
	_workflow_fx("fail")



func _set_deploy_ready_glow(on: bool) -> void:
	## Pulse doré léger sur Deploy quand la checklist est verte.
	if not is_instance_valid(deploy_btn):
		return
	if on == _deploy_ready_glow and on:
		return
	_deploy_ready_glow = on
	if _deploy_pulse_tween and _deploy_pulse_tween.is_valid():
		_deploy_pulse_tween.kill()
	if _deploy_scale_tween and _deploy_scale_tween.is_valid():
		_deploy_scale_tween.kill()
	deploy_btn.scale = Vector2.ONE
	deploy_btn.modulate = Color.WHITE
	if not on or deploy_btn.disabled:
		return
	if deploy_btn.size.x < 4.0:
		deploy_btn.pivot_offset = Vector2(80, 20)
	else:
		deploy_btn.pivot_offset = deploy_btn.size * 0.5
	_deploy_pulse_tween = create_tween()
	_deploy_pulse_tween.set_loops()
	_deploy_pulse_tween.tween_property(deploy_btn, "modulate", Color(1.15, 1.08, 0.75), 0.7).set_trans(Tween.TRANS_SINE)
	_deploy_pulse_tween.tween_property(deploy_btn, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)
	_deploy_scale_tween = create_tween()
	_deploy_scale_tween.set_loops()
	_deploy_scale_tween.tween_property(deploy_btn, "scale", Vector2(1.03, 1.03), 0.7).set_trans(Tween.TRANS_SINE)
	_deploy_scale_tween.tween_property(deploy_btn, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)


func _bump_patch_version(v: String) -> String:
	var s := v.strip_edges()
	if s == "":
		return "1.0.1"
	var parts := s.split(".")
	if parts.size() >= 3 and str(parts[2]).is_valid_int():
		parts[2] = str(int(parts[2]) + 1)
		return ".".join(parts)
	if parts.size() == 2 and str(parts[1]).is_valid_int():
		return "%s.%d.1" % [parts[0], int(parts[1])]
	if s.is_valid_int():
		return str(int(s) + 1)
	return s + ".1"


func _on_redeploy_pressed() -> void:
	if is_busy:
		return
	_fb_zone = "deploy"
	if access_token == "" or selected_game_id < 1:
		_feedback(tr_ui("redeploy_need"), "warn", "deploy")
		return
	var any_plat := (is_instance_valid(platform_web) and platform_web.button_pressed) \
		or (is_instance_valid(platform_windows) and platform_windows.button_pressed) \
		or (is_instance_valid(platform_android) and platform_android.button_pressed)
	if not any_plat:
		_feedback(tr_ui("redeploy_need"), "warn", "deploy")
		return
	var old_v := version_edit.text.strip_edges()
	if old_v == "":
		old_v = "1.0.0"
	var new_v := _bump_patch_version(old_v)
	version_edit.text = new_v
	_feedback(tr_ui("redeploy_bump") % [old_v, new_v], "info", "deploy")
	_update_deploy_checklist()
	_on_deploy_pressed()


func _on_notif_mark_all_quiet() -> void:
	if access_token == "":
		return
	_request_json(HTTPClient.METHOD_POST, "/notifications/read-all", {}, ReqKind.NOTIF_MARK_ALL)


# ══════════════════════════════════════════════════════════════════════════════
# UPLOAD STATE / PROFILES / QUEUE (v1.9.38)
# ══════════════════════════════════════════════════════════════════════════════

func _persist_upload_state() -> void:
	if _upload_file_path == "" or _upload_session_uuid == "":
		return
	var st := _DeployCore.build_upload_state(
		_upload_file_path,
		_upload_platform,
		_deploy_game_id,
		_deploy_version,
		_upload_session_uuid,
		_upload_chunk_index,
		_upload_chunks_total,
		_upload_chunk_size,
		_upload_total_bytes,
		_upload_file_sha256
	)
	_DeployCore.save_upload_state(st)


func _check_pending_upload_resume() -> void:
	var raw := _DeployCore.load_upload_state()
	var check := _DeployCore.validate_resume_state(raw)
	if not check.get("ok", false):
		if not raw.is_empty():
			_DeployCore.clear_upload_state()
		_hide_resume_banner()
		return
	_pending_resume_state = check["state"]
	_show_resume_banner(_pending_resume_state)


func _show_resume_banner(state: Dictionary) -> void:
	if not is_instance_valid(_resume_banner):
		return
	var plat := str(state.get("platform", "?"))
	var idx := int(state.get("chunk_index", 0))
	var total := int(state.get("chunks_total", 0))
	var ver := str(state.get("version", "?"))
	_resume_banner_label.text = tr_ui("resume_banner") % [plat, ver, idx, total]
	_resume_banner.visible = true
	if is_instance_valid(_resume_upload_btn):
		_resume_upload_btn.visible = true


func _hide_resume_banner() -> void:
	if is_instance_valid(_resume_banner):
		_resume_banner.visible = false
	if is_instance_valid(_resume_upload_btn):
		_resume_upload_btn.visible = false


func _on_resume_upload_pressed() -> void:
	if is_busy:
		return
	var check := _DeployCore.validate_resume_state(_pending_resume_state)
	if not check.get("ok", false):
		_feedback(tr_ui("resume_invalid"), "warn", "deploy")
		_DeployCore.clear_upload_state()
		_hide_resume_banner()
		return
	var st: Dictionary = check["state"]
	_fb_zone = "deploy"
	_set_busy(true)
	_deploy_queue.clear()
	_deploy_game_id = int(st.get("game_id", -1))
	_deploy_version = str(st.get("version", "1.0.0"))
	_upload_file_path = str(st.get("file_path", ""))
	_upload_platform = str(st.get("platform", ""))
	_upload_session_uuid = str(st.get("session_uuid", ""))
	_upload_chunk_index = int(st.get("chunk_index", 0))
	_upload_chunks_total = int(st.get("chunks_total", 0))
	_upload_chunk_size = int(st.get("chunk_size", UPLOAD_CHUNK_SIZE))
	_upload_total_bytes = int(st.get("total_bytes", 0))
	_upload_file_sha256 = str(st.get("sha256", ""))
	_upload_bytes_done = mini(_upload_chunk_index * _upload_chunk_size, _upload_total_bytes)
	_upload_is_resume = true
	_upload_speed_ema = 0.0
	_current_platform = _upload_platform
	_hide_resume_banner()
	_log(tr_ui("resume_sync") % _upload_session_uuid.substr(0, 8), "busy")
	_feedback(tr_ui("resume_sync_fb"), "busy", "deploy")
	# Resync serveur avant d’envoyer des chunks
	_request_json(
		HTTPClient.METHOD_GET,
		"/developer/uploads/%s" % _upload_session_uuid,
		{},
		ReqKind.UPLOAD_STATUS
	)


## Après GET /developer/uploads/{uuid} — aligne l’index sur received_chunks serveur.
func _handle_upload_status(code: int, data: Variant) -> void:
	if code == 404 or code == 410:
		_log(tr_ui("resume_session_gone"), "warn")
		_feedback(tr_ui("resume_session_gone"), "warn", "deploy")
		_DeployCore.clear_upload_state()
		_pending_resume_state = {}
		_set_busy(false)
		return
	if code < 200 or code >= 300 or typeof(data) != TYPE_DICTIONARY:
		var msg := _api_error_message(data, code)
		_log("Status upload HTTP %d: %s" % [code, msg], "err")
		_feedback(tr_ui("resume_status_fail") % msg, "err", "deploy")
		_set_busy(false)
		return

	var status := str(data.get("status", ""))
	if status in ["expired", "aborted", "complete"]:
		_log(tr_ui("resume_session_status") % status, "warn")
		_feedback(tr_ui("resume_session_status") % status, "warn", "deploy")
		_DeployCore.clear_upload_state()
		_pending_resume_state = {}
		_set_busy(false)
		return

	# Sync métadonnées serveur
	_upload_chunks_total = int(data.get("total_chunks", _upload_chunks_total))
	_upload_chunk_size = int(data.get("chunk_size", _upload_chunk_size))
	var total_size := int(data.get("total_size", _upload_total_bytes))
	if total_size > 0:
		_upload_total_bytes = total_size
	var srv_hash := str(data.get("sha256", ""))
	if srv_hash != "" and _upload_file_sha256 != "" and srv_hash != _upload_file_sha256:
		_log(tr_ui("checksum_mismatch") % [_upload_file_sha256.substr(0, 12), srv_hash.substr(0, 12)], "err")
		_feedback(tr_ui("checksum_mismatch_fb"), "err", "deploy")
		_DeployCore.clear_upload_state()
		_set_busy(false)
		return

	# Premier index manquant côté serveur
	var received = data.get("received_chunks", [])
	var have := {}
	if typeof(received) == TYPE_ARRAY:
		for c in received:
			have[int(c)] = true
	_upload_chunk_index = 0
	while _upload_chunk_index < _upload_chunks_total and have.has(_upload_chunk_index):
		_upload_chunk_index += 1
	_upload_bytes_done = mini(_upload_chunk_index * _upload_chunk_size, _upload_total_bytes)
	_upload_is_resume = _upload_chunk_index > 0
	_persist_upload_state()

	if _upload_chunk_index >= _upload_chunks_total and _upload_chunks_total > 0:
		_log(tr_ui("resume_all_chunks"), "info")
		_complete_resumable_upload()
		return

	_log(tr_ui("resume_start") % [_upload_platform, _upload_chunk_index + 1, _upload_chunks_total], "busy")
	_feedback(tr_ui("resume_start_fb") % _upload_platform, "busy", "deploy")
	_upload_update_progress_ui(false)
	_update_queue_status_ui()
	_send_next_chunk()


func _on_discard_resume_pressed() -> void:
	_DeployCore.clear_upload_state()
	_pending_resume_state = {}
	_hide_resume_banner()
	_feedback(tr_ui("resume_discarded"), "info", "deploy")


func _load_deploy_profiles() -> void:
	_deploy_profiles = _Profiles.load_all()
	_refresh_profile_option()


func _refresh_profile_option() -> void:
	if not is_instance_valid(_profile_option):
		return
	_profile_option.clear()
	_profile_option.add_item(tr_ui("profile_none"), -1)
	var names: Array = _deploy_profiles.keys()
	names.sort()
	var i := 0
	for n in names:
		_profile_option.add_item(str(n), i)
		i += 1


func _on_profile_selected(idx: int) -> void:
	if not is_instance_valid(_profile_option) or idx <= 0:
		return
	var name := _profile_option.get_item_text(idx)
	if not _deploy_profiles.has(name):
		return
	var p: Dictionary = _deploy_profiles[name]
	if is_instance_valid(platform_web):
		platform_web.button_pressed = bool(p.get("web", false))
	if is_instance_valid(platform_windows):
		platform_windows.button_pressed = bool(p.get("windows", false))
	if is_instance_valid(platform_android):
		platform_android.button_pressed = bool(p.get("android", false))
	_select_preset_by_name(preset_web, str(p.get("preset_web", "")))
	_select_preset_by_name(preset_windows, str(p.get("preset_windows", "")))
	_select_preset_by_name(preset_android, str(p.get("preset_android", "")))
	if is_instance_valid(_profile_name_edit):
		_profile_name_edit.text = name
	_update_deploy_checklist()
	_feedback(tr_ui("profile_loaded") % name, "ok", "deploy")


func _select_preset_by_name(opt: OptionButton, pname: String) -> void:
	if not is_instance_valid(opt) or pname == "":
		return
	for i in range(opt.item_count):
		var t := str(opt.get_item_text(i))
		if t == pname or t.begins_with(pname):
			opt.select(i)
			return


func _on_profile_save_pressed() -> void:
	var name := ""
	if is_instance_valid(_profile_name_edit):
		name = _profile_name_edit.text.strip_edges()
	if name == "":
		_feedback(tr_ui("profile_name_required"), "warn", "deploy")
		return
	var data := _Profiles.capture_from_ui(
		is_instance_valid(platform_web) and platform_web.button_pressed,
		is_instance_valid(platform_windows) and platform_windows.button_pressed,
		is_instance_valid(platform_android) and platform_android.button_pressed,
		str(preset_web.get_item_text(preset_web.selected)) if is_instance_valid(preset_web) and preset_web.selected >= 0 else "",
		str(preset_windows.get_item_text(preset_windows.selected)) if is_instance_valid(preset_windows) and preset_windows.selected >= 0 else "",
		str(preset_android.get_item_text(preset_android.selected)) if is_instance_valid(preset_android) and preset_android.selected >= 0 else "",
	)
	_deploy_profiles = _Profiles.save_profile(name, data, _deploy_profiles)
	_refresh_profile_option()
	_feedback(tr_ui("profile_saved") % name, "ok", "deploy")


func _on_profile_delete_pressed() -> void:
	if not is_instance_valid(_profile_option) or _profile_option.selected <= 0:
		_feedback(tr_ui("profile_select_first"), "warn", "deploy")
		return
	var name := _profile_option.get_item_text(_profile_option.selected)
	_deploy_profiles = _Profiles.delete_profile(name, _deploy_profiles)
	_refresh_profile_option()
	_feedback(tr_ui("profile_deleted") % name, "info", "deploy")


func _update_queue_status_ui() -> void:
	if not is_instance_valid(_queue_status_label):
		return
	var remaining := _deploy_queue.size()
	var current := _current_platform
	if is_busy and current != "":
		# +1 for current in progress
		var total_hint := remaining + 1
		_queue_status_label.text = tr_ui("queue_status") % [current, remaining]
		_queue_status_label.visible = true
		_queue_status_label.modulate = C_BUSY
	elif is_busy:
		_queue_status_label.text = tr_ui("queue_busy")
		_queue_status_label.visible = true
		_queue_status_label.modulate = C_BUSY
	else:
		_queue_status_label.visible = false


# ══════════════════════════════════════════════════════════════════════════════
# DEPLOY PIPELINE
# ══════════════════════════════════════════════════════════════════════════════

var _deploy_queue: Array = []  # [{platform, preset_name, preset_idx}]
var _deploy_game_id: int = -1
var _deploy_version: String = "1.0.0"
var _current_export_path: String = ""
var _current_zip_path: String = ""
var _current_platform: String = ""


func _on_deploy_pressed() -> void:
	if is_busy:
		return
	_fb_zone = "deploy"
	_update_deploy_checklist()
	# Preflight bloquant — tout doit être vert
	var issues := _preflight_issues()
	if not issues.is_empty():
		_show_preflight_block(issues)
		return
	if is_instance_valid(_preflight_panel):
		_preflight_panel.visible = false

	_deploy_queue.clear()
	_deploy_game_id = selected_game_id
	_deploy_version = version_edit.text.strip_edges()
	if _deploy_version == "":
		_deploy_version = "1.0.0"

	if platform_web.button_pressed:
		var pidx := preset_web.get_selected_id()
		var pname := preset_web.get_item_text(preset_web.selected)
		_deploy_queue.append({"platform": "web", "preset_name": pname, "preset_idx": pidx})

	if platform_windows.button_pressed:
		var pidx := preset_windows.get_selected_id()
		var pname := preset_windows.get_item_text(preset_windows.selected)
		_deploy_queue.append({"platform": "windows", "preset_name": pname, "preset_idx": pidx})

	if platform_android.button_pressed:
		var pidx := preset_android.get_selected_id()
		var pname := preset_android.get_item_text(preset_android.selected)
		_deploy_queue.append({"platform": "android", "preset_name": pname, "preset_idx": pidx})

	if _deploy_queue.is_empty():
		_feedback(tr_ui("plat_required"), "warn")
		return

	_set_busy(true)
	progress_bar.value = 0
	var plat_names: PackedStringArray = []
	for item in _deploy_queue:
		plat_names.append(str(item.get("platform", "?")))
	var plats := ", ".join(plat_names)
	_log("═══ Déploiement jeu #%d — plateformes : %s ═══" % [_deploy_game_id, plats], "busy")
	_feedback(tr_ui("deploy_start") % plats, "busy")
	_workflow_fx("deploy_start")
	_sfx_play("confirm")
	_update_queue_status_ui()
	_process_next_deploy()


func _process_next_deploy() -> void:
	if _deploy_queue.is_empty():
		_current_platform = ""
		_update_queue_status_ui()
		_set_step("Déploiement terminé ✔", 100)
		_feedback(tr_ui("deploy_all_ok"), "ok")
		_comfort_on_success()
		_set_busy(false)
		_request_my_games()
		_on_ship_success()
		return

	var item: Dictionary = _deploy_queue.pop_front()
	_current_platform = str(item["platform"])
	_update_queue_status_ui()
	var preset_name: String = str(item["preset_name"])
	# remove " (?)" if any
	if preset_name.ends_with(" (?)"):
		preset_name = preset_name.substr(0, preset_name.length() - 4)

	_set_step("Export %s (%s)…" % [_current_platform, preset_name], 10)
	_log("Export preset « %s » → plateforme %s" % [preset_name, _current_platform])
	_workflow_fx("export")

	# Dossier temporaire
	var tmp_dir := OS.get_cache_dir().path_join("thiossane_export_%s" % _current_platform)
	DirAccess.make_dir_recursive_absolute(tmp_dir)

	# Chemin de sortie selon plateforme
	# Web : Godot attend un fichier .html (pas un dossier)
	match _current_platform:
		"web":
			_current_export_path = tmp_dir.path_join("index.html")
		"windows":
			_current_export_path = tmp_dir.path_join("game.exe")
		"android":
			_current_export_path = tmp_dir.path_join("game.apk")
		_:
			_current_export_path = tmp_dir.path_join("build")

	# EditorInterface n'expose pas export_project : on utilise le CLI headless
	# (fiable sous Godot 4.2+ tant que les templates d'export sont installés).
	var ok := _export_via_cli(preset_name, _current_export_path)

	var export_exists := FileAccess.file_exists(_current_export_path) \
		or DirAccess.dir_exists_absolute(_current_export_path)
	if not export_exists and _current_platform == "windows":
		var pck_alt := _current_export_path.get_basename() + ".pck"
		export_exists = FileAccess.file_exists(pck_alt)
	if not export_exists and _current_platform == "web":
		# Godot écrit index.html + .js/.wasm/.pck dans le même dossier
		var parent_dir := _current_export_path.get_base_dir()
		export_exists = FileAccess.file_exists(parent_dir.path_join("index.html"))

	if not ok or not export_exists:
		_log(tr_ui("export_fail") % _current_platform, "err")
		_feedback(tr_ui("export_fail") % _current_platform, "err")
		_workflow_fx("fail")
		_sfx_play("error")
		_process_next_deploy()
		return

	_set_step("Compression ZIP…", 40)
	_current_zip_path = _zip_export(_current_export_path, _current_platform)
	if _current_zip_path == "":
		_log("Échec compression.")
		_process_next_deploy()
		return

	_set_step("Envoi du build (%s)…" % _current_platform, 60)
	_upload_build(_current_zip_path, _current_platform)


func _export_via_cli(preset_name: String, path: String) -> bool:
	var godot_exe := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	# Note: lance un 2e processus Godot headless. Les templates d'export
	# doivent être installés (Éditeur → Gérer les templates d'export).
	var args := PackedStringArray([
		"--headless",
		"--path", project_path,
		"--export-release", preset_name,
		path,
	])
	_log("CLI: %s %s" % [godot_exe, " ".join(args)])
	var output: Array = []
	var exit_code := OS.execute(godot_exe, args, output, true, false)
	for line in output:
		_log("  " + str(line))
	if exit_code != 0:
		_log("Export exit_code=%d. Vérifiez le nom exact du preset et les templates." % exit_code)
	return exit_code == 0


func _zip_export(src_path: String, platform: String) -> String:
	var zip_path := OS.get_cache_dir().path_join("thiossane_%s_%s.zip" % [platform, _deploy_version.replace(".", "_")])
	# Si c'est déjà un .apk, envoi direct (pas de re-zip).
	if platform == "android" and src_path.ends_with(".apk") and FileAccess.file_exists(src_path):
		_log("APK détecté, envoi direct (pas de re-zip).")
		return src_path

	var packer := ZIPPacker.new()
	var err := packer.open(zip_path, ZIPPacker.APPEND_CREATE)
	if err != OK:
		_log("Impossible de créer le ZIP: %s" % error_string(err))
		return ""

	# Web : zipper tout le dossier parent (index.html + .js + .wasm + .pck + …)
	if platform == "web":
		var folder := src_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(folder):
			_log("Dossier d'export web introuvable: %s" % folder)
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
			_zip_write_stream(packer, f)
			f.close()
		packer.close_file()
		# Inclure aussi le .pck à côté de l'exe
		var pck := src_path.get_basename() + ".pck"
		if FileAccess.file_exists(pck):
			packer.start_file(pck.get_file())
			var f2 := FileAccess.open(pck, FileAccess.READ)
			if f2:
				_zip_write_stream(packer, f2)
				f2.close()
			packer.close_file()
	else:
		_log("Chemin d'export introuvable: %s" % src_path)
		packer.close()
		return ""

	packer.close()
	var size := 0
	if FileAccess.file_exists(zip_path):
		var fz := FileAccess.open(zip_path, FileAccess.READ)
		if fz:
			size = fz.get_length()
			fz.close()
	_log("ZIP créé: %s (%.1f Mo)" % [zip_path, size / 1048576.0])
	return zip_path


func _zip_write_stream(packer: ZIPPacker, f: FileAccess) -> void:
	## Écrit le fichier dans le ZIP par blocs de 4 Mo (évite de charger un build entier en RAM).
	while f.get_position() < f.get_length():
		packer.write_file(f.get_buffer(4 * 1024 * 1024))


func _add_folder_to_zip(packer: ZIPPacker, folder: String, prefix: String) -> void:
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
				_zip_write_stream(packer, f)
				f.close()
			packer.close_file()
		fname = dir.get_next()
	dir.list_dir_end()


func _upload_build(file_path: String, platform: String) -> void:
	if not FileAccess.file_exists(file_path):
		_log("Fichier à uploader introuvable: %s" % file_path)
		_process_next_deploy()
		return

	var file_size := 0
	var fcheck := FileAccess.open(file_path, FileAccess.READ)
	if fcheck:
		file_size = fcheck.get_length()
		fcheck.close()
	else:
		_log("Impossible d'ouvrir le fichier: %s" % file_path)
		_process_next_deploy()
		return

	var size_mb := file_size / 1048576.0
	if file_size > MAX_BUILD_BYTES:
		_log(tr_ui("build_too_large") % [size_mb, MAX_BUILD_MB])
		_feedback(tr_ui("build_too_large") % [size_mb, MAX_BUILD_MB], "err")
		_process_next_deploy()
		return
	if size_mb > MAX_UPLOAD_WARN_MB:
		_log("Attention : build volumineux (%.1f Mo / max %d Mo). Upload résumable par chunks." % [size_mb, MAX_BUILD_MB])

	_upload_file_path = file_path
	_upload_platform = platform
	_upload_chunk_index = 0
	_upload_chunks_total = 0
	_upload_session_uuid = ""
	_upload_chunk_size = UPLOAD_CHUNK_SIZE
	_upload_total_bytes = file_size
	_upload_bytes_done = 0
	_upload_speed_ema = 0.0
	_upload_chunk_started_msec = 0
	_upload_chunk_bytes = 0
	_upload_is_resume = false
	_upload_file_sha256 = _DeployCore.file_sha256(file_path)
	if _upload_file_sha256 != "":
		_log("SHA-256 build : %s…" % _upload_file_sha256.substr(0, 16))
	_upload_detail_show(tr_ui("upload_init_detail") % [size_mb, platform])

	var file_name := file_path.get_file()
	_log("Init upload résumable %s (%.1f Mo) → %s" % [file_name, size_mb, platform])
	_set_step(tr_ui("upload_init_step") % platform, 50)

	var body := {
		"game_id": _deploy_game_id,
		"version_number": _deploy_version,
		"platform": platform,
		"filename": file_name,
		"total_size": file_size,
		"chunk_size": UPLOAD_CHUNK_SIZE,
		"sha256": _upload_file_sha256,
	}
	_request_json(HTTPClient.METHOD_POST, "/developer/uploads/init", body, ReqKind.UPLOAD_INIT)


func _handle_upload_init(code: int, data: Variant) -> void:
	if code < 200 or code >= 300 or typeof(data) != TYPE_DICTIONARY:
		var msg := _api_error_message(data, code)
		_log("Init upload échoué HTTP %d: %s" % [code, msg])
		_feedback(tr_ui("upload_fail") % msg, "err")
		_upload_detail_hide()
		_process_next_deploy()
		return

	_upload_session_uuid = str(data.get("uuid", ""))
	_upload_chunk_size = int(data.get("chunk_size", UPLOAD_CHUNK_SIZE))
	_upload_chunks_total = int(data.get("total_chunks", 0))
	var received = data.get("received_chunks", [])
	_upload_is_resume = false
	if typeof(received) == TYPE_ARRAY and received.size() > 0:
		# Resume: find first missing
		var have := {}
		for c in received:
			have[int(c)] = true
		_upload_chunk_index = 0
		while _upload_chunk_index < _upload_chunks_total and have.has(_upload_chunk_index):
			_upload_chunk_index += 1
		_upload_is_resume = _upload_chunk_index > 0
		# Octets déjà sur le serveur (approx. : chunks complets ; dernier chunk peut être plus petit)
		_upload_bytes_done = mini(_upload_chunk_index * _upload_chunk_size, _upload_total_bytes)
		_log(tr_ui("upload_resuming") % [_upload_platform, _upload_chunk_index + 1, _upload_chunks_total])
		var done_mb := _upload_bytes_done / 1048576.0
		var total_mb := _upload_total_bytes / 1048576.0
		_feedback(tr_ui("upload_resume_fb") % [done_mb, total_mb, _upload_chunk_index, _upload_chunks_total], "info")
	else:
		_upload_chunk_index = 0
		_upload_bytes_done = 0

	if _upload_session_uuid == "" or _upload_chunks_total <= 0:
		_log("Init upload: réponse invalide (uuid/total_chunks)")
		_feedback(tr_ui("upload_fail") % "invalid init", "err")
		_upload_detail_hide()
		_process_next_deploy()
		return

	_persist_upload_state()
	_upload_update_progress_ui(false)
	_send_next_chunk()


func _send_next_chunk() -> void:
	if _upload_chunk_index >= _upload_chunks_total:
		_complete_resumable_upload()
		return

	var f := FileAccess.open(_upload_file_path, FileAccess.READ)
	if f == null:
		_log("Impossible d'ouvrir le fichier pour chunk")
		_feedback(tr_ui("upload_fail") % "file open", "err")
		_upload_detail_hide()
		_process_next_deploy()
		return

	var offset := _upload_chunk_index * _upload_chunk_size
	f.seek(offset)
	var remaining := f.get_length() - offset
	var to_read := mini(_upload_chunk_size, remaining)
	var chunk_data := f.get_buffer(to_read)
	f.close()
	_upload_chunk_bytes = chunk_data.size()
	_upload_chunk_started_msec = Time.get_ticks_msec()

	var url := "%s/developer/uploads/%s/chunk" % [_api_base(), _upload_session_uuid]
	var headers := PackedStringArray([
		"Content-Type: application/octet-stream",
		"Accept: application/json",
		"Connection: close",
		"Upload-Chunk-Index: %d" % _upload_chunk_index,
		"Authorization: Bearer " + access_token,
		"X-Access-Token: " + access_token,
	])

	_upload_update_progress_ui(true)
	_log(tr_ui("upload_chunk_sending") % [_upload_chunk_index + 1, _upload_chunks_total, _upload_chunk_bytes / 1048576.0])

	var err := upload_http.request_raw(url, headers, HTTPClient.METHOD_PUT, chunk_data)
	if err != OK:
		_log("Erreur envoi chunk: %s" % error_string(err))
		_feedback(tr_ui("upload_fail") % error_string(err), "err")
		_upload_detail_hide()
		_process_next_deploy()


func _complete_resumable_upload() -> void:
	_log("Assemblage final upload %s…" % _upload_platform)
	_set_step(tr_ui("upload_finalize_step") % _upload_platform, 92)
	_upload_detail_show(tr_ui("upload_finalize_detail"))
	_request_json(
		HTTPClient.METHOD_POST,
		"/developer/uploads/%s/complete" % _upload_session_uuid,
		{},
		ReqKind.UPLOAD_COMPLETE
	)


func _handle_upload_complete(code: int, data: Variant) -> void:
	if code >= 200 and code < 300:
		_log("Upload résumable OK pour %s" % _upload_platform, "ok")
		if typeof(data) == TYPE_DICTIONARY:
			_log("  → version id=%s size=%s" % [str(data.get("id", "?")), str(data.get("file_size_mo", "?"))], "ok")
			# Vérif checksum côté serveur si renvoyé
			var srv_hash := str(data.get("sha256", data.get("checksum", "")))
			var checksum_ok = data.get("checksum_ok", null)
			if checksum_ok == false or (srv_hash != "" and _upload_file_sha256 != "" and srv_hash != _upload_file_sha256):
				_log(tr_ui("checksum_mismatch") % [_upload_file_sha256.substr(0, 12), srv_hash.substr(0, 12)], "warn")
				_feedback(tr_ui("checksum_mismatch_fb"), "warn")
			elif srv_hash != "" or _upload_file_sha256 != "":
				var shown := srv_hash if srv_hash != "" else _upload_file_sha256
				_log(tr_ui("checksum_ok") % shown.substr(0, 16), "ok")
		_DeployCore.clear_upload_state()
		_pending_resume_state = {}
		_hide_resume_banner()
		_set_step(tr_ui("upload_ok_step") % _upload_platform, 95)
		_feedback(tr_ui("upload_ok") % _upload_platform, "ok")
		_workflow_fx("upload")
		_upload_detail_show(tr_ui("upload_done_detail") % _format_bytes(_upload_total_bytes))
		_complete_onboarding_if_needed()
		if _current_zip_path != "" and _current_zip_path.ends_with(".zip") and FileAccess.file_exists(_current_zip_path):
			DirAccess.remove_absolute(_current_zip_path)
	else:
		var msg := _api_error_message(data, code)
		_log("Complete upload HTTP %d: %s" % [code, msg])
		_feedback(tr_ui("upload_fail") % msg, "err")
		_upload_detail_hide()
	_process_next_deploy()


func _on_upload_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	# Réponse d'un chunk PUT
	var text := body.get_string_from_utf8()
	var data: Variant = null
	if text.strip_edges() != "":
		var json := JSON.new()
		if json.parse(text) == OK:
			data = json.get_data()

	if result != HTTPRequest.RESULT_SUCCESS:
		_log("Chunk réseau échoué (result=%d — %s)" % [result, _http_result_name(result)])
		_feedback(tr_ui("upload_net_fail"), "err")
		_upload_detail_show(tr_ui("upload_interrupted") % [
			_format_bytes(_upload_bytes_done),
			_format_bytes(_upload_total_bytes),
		])
		_process_next_deploy()
		return

	if response_code == 401 and refresh_token != "" and not _refreshing_token:
		_log("401 pendant chunk — refresh puis reprise…")
		_retry_after_refresh = {"kind": "upload_chunk"}
		_try_refresh_token()
		return

	if response_code < 200 or response_code >= 300:
		var msg := _api_error_message(data, response_code)
		_log("Chunk HTTP %d: %s" % [response_code, msg if msg else text.left(200)])
		_feedback(tr_ui("upload_fail") % msg, "err")
		_upload_detail_show(tr_ui("upload_interrupted") % [
			_format_bytes(_upload_bytes_done),
			_format_bytes(_upload_total_bytes),
		])
		_process_next_deploy()
		return

	# Succès : mesurer débit sur ce chunk
	var elapsed_ms := maxi(Time.get_ticks_msec() - _upload_chunk_started_msec, 1)
	var instant_bps := float(_upload_chunk_bytes) / (float(elapsed_ms) / 1000.0)
	if _upload_speed_ema <= 0.0:
		_upload_speed_ema = instant_bps
	else:
		_upload_speed_ema = lerpf(_upload_speed_ema, instant_bps, 0.35)
	_upload_bytes_done = mini(_upload_bytes_done + _upload_chunk_bytes, _upload_total_bytes)
	_upload_chunk_index += 1
	_persist_upload_state()

	_log(tr_ui("upload_chunk_ok") % [
		_upload_chunk_index,
		_upload_chunks_total,
		_format_speed(_upload_speed_ema),
	])
	_upload_update_progress_ui(false)

	if typeof(data) == TYPE_DICTIONARY and data.get("complete", false):
		_complete_resumable_upload()
	else:
		_send_next_chunk()


## ── Helpers progression upload ───────────────────────────────────────────────

func _format_bytes(n: int) -> String:
	if n < 1024:
		return "%d o" % n
	if n < 1048576:
		return "%.1f Ko" % (n / 1024.0)
	if n < 1073741824:
		return "%.2f Mo" % (n / 1048576.0)
	return "%.2f Go" % (n / 1073741824.0)


func _format_speed(bps: float) -> String:
	if bps <= 0.0:
		return "—"
	if bps < 1024.0:
		return "%.0f o/s" % bps
	if bps < 1048576.0:
		return "%.1f Ko/s" % (bps / 1024.0)
	return "%.2f Mo/s" % (bps / 1048576.0)


func _format_eta(seconds: float) -> String:
	if seconds < 0.0 or not is_finite(seconds):
		return "—"
	var s := int(ceili(seconds))
	if s < 60:
		return tr_ui("upload_eta_s") % s
	var m := s / 60
	var rs := s % 60
	if m < 60:
		return tr_ui("upload_eta_ms") % [m, rs]
	var h := m / 60
	var rm := m % 60
	return tr_ui("upload_eta_hm") % [h, rm]


func _upload_detail_show(msg: String) -> void:
	if is_instance_valid(upload_detail_label):
		upload_detail_label.visible = true
		upload_detail_label.text = msg
		upload_detail_label.modulate = C_MUTED


func _upload_detail_hide() -> void:
	if is_instance_valid(upload_detail_label):
		upload_detail_label.visible = false
		upload_detail_label.text = ""


func _upload_update_progress_ui(sending: bool) -> void:
	var total := maxi(_upload_total_bytes, 1)
	var done := clampi(_upload_bytes_done, 0, total)
	# Plage pipeline déploiement : 50 → 90 % pendant les chunks
	var pct := 50.0 + 40.0 * (float(done) / float(total))
	if sending and _upload_chunk_bytes > 0:
		# léger avance visuelle pendant l'envoi du chunk courant
		pct = 50.0 + 40.0 * (float(done) + float(_upload_chunk_bytes) * 0.15) / float(total)
	pct = clampf(pct, 50.0, 90.0)

	var remain := maxi(total - done, 0)
	var eta_str := "—"
	if _upload_speed_ema > 1.0 and remain > 0:
		eta_str = _format_eta(float(remain) / _upload_speed_ema)

	var prefix := tr_ui("upload_resume_tag") if _upload_is_resume and done > 0 else ""
	var line := tr_ui("upload_progress_line") % [
		_format_bytes(done),
		_format_bytes(total),
		_format_speed(_upload_speed_ema),
		eta_str,
		_upload_chunk_index + (1 if sending else 0),
		_upload_chunks_total,
	]
	if prefix != "":
		line = prefix + " " + line

	# Mise à jour UI sans spammer le journal (contrairement à _set_step)
	if is_instance_valid(step_label):
		step_label.text = tr_ui("upload_step_line") % [_upload_platform, _format_bytes(done), _format_bytes(total)]
		step_label.modulate = C_BUSY if is_busy else C_INFO
	if is_instance_valid(progress_bar):
		progress_bar.value = pct
	_upload_detail_show(line)


func _multipart_field(boundary: String, name: String, value: String) -> PackedByteArray:
	var s := "--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [boundary, name, value]
	return s.to_utf8_buffer()


func _multipart_file(boundary: String, name: String, filename: String, data: PackedByteArray) -> PackedByteArray:
	var header := "--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: application/octet-stream\r\n\r\n" % [boundary, name, filename]
	var tail := "\r\n".to_utf8_buffer()
	var out := header.to_utf8_buffer()
	out.append_array(data)
	out.append_array(tail)
	return out


# ══════════════════════════════════════════════════════════════════════════════
# RESUBMIT
# ══════════════════════════════════════════════════════════════════════════════

func _on_resubmit_pressed() -> void:
	if is_busy:
		return
	_fb_zone = "deploy"
	if access_token == "" or selected_game_id < 1:
		_feedback(tr_ui("resubmit_need"), "warn", "deploy")
		return
	_set_busy(true)
	_set_step("Soumission à la modération…", 50)
	_request_json(HTTPClient.METHOD_POST, "/developer/games/%d/resubmit" % selected_game_id, {}, ReqKind.RESUBMIT)


func _handle_resubmit(code: int, data: Variant) -> void:
	_set_busy(false)
	if code >= 200 and code < 300:
		_log("Jeu soumis pour modération.")
		_feedback(tr_ui("resubmit_ok"), "ok")
		_set_step("Soumis ✔", 100)
		_request_my_games()
	else:
		var msg := _api_error_message(data, code)
		_log("Resubmit HTTP %d: %s" % [code, msg])
		_feedback(tr_ui("resubmit_fail") % msg, "err")



# ══════════════════════════════════════════════════════════════════════════════
# SHARE LINK (intégration API POST /developer/games/{id}/share-link)
# ══════════════════════════════════════════════════════════════════════════════

func _clear_share_ui() -> void:
	_current_share = {}
	if is_instance_valid(share_url_edit):
		share_url_edit.text = ""
		share_url_edit.placeholder_text = tr_ui("share_empty")
	if is_instance_valid(share_stats_label):
		share_stats_label.text = tr_ui("share_stats_line") % [0, 0]


func _store_base() -> String:
	var b := "https://www.thiossane.store/"
	if is_instance_valid(store_base_edit):
		b = store_base_edit.text.strip_edges()
	if b == "":
		b = "https://www.thiossane.store/"
	if not b.ends_with("/"):
		b += "/"
	return b


func _full_share_url(path: String) -> String:
	# path renvoyé par l'API : "game.html?id=X&ref=TOKEN"
	var p := path.strip_edges()
	if p.begins_with("/"):
		p = p.substr(1)
	return _store_base() + p


func _on_share_generate_pressed() -> void:
	if is_busy:
		return
	if access_token == "":
		_feedback(tr_ui("connect_first"), "warn")
		return
	if selected_game_id < 1:
		_feedback(tr_ui("share_need_game"), "warn")
		return
	# Le backend refuse si le jeu n'est pas approved (sauf admin)
	var st := selected_game_status.to_lower()
	if st != "" and st != "approved" and st != "APPROVED":
		# on tente quand même : le serveur renverra le message exact
		_log("Statut jeu=%s — le backend exige « approved » pour un lien public." % selected_game_status)

	var body: Dictionary = {}
	var label := ""
	if is_instance_valid(share_label_edit):
		label = share_label_edit.text.strip_edges()
	if label != "":
		body["label"] = label
	if is_instance_valid(campaign_edit):
		var camp := campaign_edit.text.strip_edges()
		if camp != "":
			body["campaign_name"] = camp
	if is_instance_valid(channel_edit):
		var ch := channel_edit.text.strip_edges()
		if ch != "":
			body["channel"] = ch
	if is_instance_valid(share_force_check) and share_force_check.button_pressed:
		body["force_new"] = true

	_set_busy(true)
	_log("Demande share-link pour jeu #%d…" % selected_game_id)
	_request_json(
		HTTPClient.METHOD_POST,
		_ShareApi.share_link_path(selected_game_id),
		body,
		ReqKind.SHARE_LINK
	)


func _handle_share_link(code: int, data: Variant) -> void:
	_set_busy(false)
	if code >= 200 and code < 300 and typeof(data) == TYPE_DICTIONARY:
		_current_share = data
		var path := str(data.get("path", ""))
		var url := _full_share_url(path)
		if is_instance_valid(share_url_edit):
			share_url_edit.text = url
		var clicks := int(data.get("clicks", 0))
		var uniq := int(data.get("unique_clicks", 0))
		if is_instance_valid(share_stats_label):
			share_stats_label.text = tr_ui("share_stats_line") % [clicks, uniq]
		_log("ShareLink OK token=%s clicks=%d unique=%d" % [str(data.get("token", "")), clicks, uniq])
		_feedback(tr_ui("share_ok") % [clicks, uniq], "ok")
		_save_config()
	else:
		var msg := _api_error_message(data, code)
		_log("ShareLink HTTP %d: %s" % [code, msg])
		_feedback(tr_ui("share_fail") % msg, "err")


func _on_share_stats_pressed() -> void:
	if is_busy:
		return
	if access_token == "":
		_feedback(tr_ui("connect_first"), "warn")
		return
	_set_busy(true)
	_request_json(HTTPClient.METHOD_GET, _ShareApi.share_stats_path(), {}, ReqKind.SHARE_STATS)


func _handle_share_stats(code: int, data: Variant) -> void:
	_set_busy(false)
	if code >= 200 and code < 300 and typeof(data) == TYPE_DICTIONARY:
		var total_c := int(data.get("total_clicks", 0))
		var total_u := int(data.get("total_unique_clicks", 0))
		var total_l := int(data.get("total_links", 0))
		_log("Share stats globales : %d liens, %d clics, %d uniques" % [total_l, total_c, total_u])
		# Si le jeu courant a des stats dans by_game, les afficher
		var by_game = data.get("by_game", [])
		if typeof(by_game) == TYPE_ARRAY and selected_game_id > 0:
			for row in by_game:
				if typeof(row) == TYPE_DICTIONARY and int(row.get("game_id", -1)) == selected_game_id:
					var c := int(row.get("clicks", row.get("click_count", 0)))
					var u := int(row.get("unique_clicks", row.get("unique_click_count", 0)))
					if is_instance_valid(share_stats_label):
						share_stats_label.text = tr_ui("share_stats_line") % [c, u]
					_feedback(tr_ui("share_ok") % [c, u], "ok")
					return
		if is_instance_valid(share_stats_label):
			share_stats_label.text = tr_ui("share_stats_line") % [total_c, total_u]
		_feedback(tr_ui("share_ok") % [total_c, total_u], "ok")
	else:
		var msg := _api_error_message(data, code)
		_log("Share stats HTTP %d: %s" % [code, msg])
		_feedback(tr_ui("share_fail") % msg, "err")




func _on_share_copy_link() -> void:
	var url := ""
	if is_instance_valid(share_url_edit):
		url = share_url_edit.text.strip_edges()
	if url == "":
		_feedback(tr_ui("share_empty"), "warn")
		return
	DisplayServer.clipboard_set(url)
	_feedback(tr_ui("share_copied"), "ok")
	_log("Lien copié: %s" % url)







func _on_mkt_analytics_pressed() -> void:
	if is_busy:
		return
	if access_token == "":
		_feedback(tr_ui("connect_first"), "warn")
		return
	_set_busy(true)
	var path := "/developer/marketing/analytics"
	if selected_game_id > 0:
		path += "?game_id=%d" % selected_game_id
	_request_json(HTTPClient.METHOD_GET, path, {}, ReqKind.MKT_ANALYTICS)


func _handle_mkt_analytics(code: int, data: Variant) -> void:
	_set_busy(false)
	if code < 200 or code >= 300 or typeof(data) != TYPE_DICTIONARY:
		var msg := _api_error_message(data, code)
		_log("Marketing analytics HTTP %d: %s" % [code, msg])
		_feedback(tr_ui("share_fail") % msg, "err")
		return
	var summary = data.get("summary", {})
	if typeof(summary) != TYPE_DICTIONARY:
		summary = {}
	var sales := int(summary.get("total_sales", 0))
	var revenue := float(summary.get("total_revenue", 0.0))
	var uniq := int(summary.get("total_unique_clicks", 0))
	var conv := float(summary.get("overall_conversion_pct", 0.0))
	var clicks := int(summary.get("total_clicks", 0))
	if is_instance_valid(mkt_sales_label):
		mkt_sales_label.text = _fmt("mkt_sales_line", [sales, revenue])
	if is_instance_valid(share_stats_label):
		share_stats_label.text = tr_ui("share_stats_line") % [clicks, uniq]
	_log("Marketing: %d clics, %d uniques, %d ventes, revenu %.0f, conv %.1f%%" % [clicks, uniq, sales, revenue, conv])
	_feedback(_fmt("mkt_conv_line", [conv, uniq]), "ok")
	var by_camp = data.get("by_campaign", [])
	if typeof(by_camp) == TYPE_ARRAY:
		for row in by_camp:
			if typeof(row) == TYPE_DICTIONARY:
				_log("  campagne «%s»: clics=%s ventes=%s revenu=%s" % [
					str(row.get("campaign", "?")),
					str(row.get("clicks", 0)),
					str(row.get("sales", 0)),
					str(row.get("revenue", 0)),
				])


# ══════════════════════════════════════════════════════════════════════════════
# MASCOTTE THIOSSANE — apparitions fun & un peu bizarres
# ══════════════════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════════════════════
# MASCOTTE + CÉLÉBRATION SHIP
# ══════════════════════════════════════════════════════════════════════════════

var _mascot_layer: Control
var _mascot_root: VBoxContainer
var _mascot_tex: TextureRect
var _mascot_sprite_box: Control
var _mascot_outfit: Control
var _mascot_bubble: PanelContainer
var _mascot_bubble_label: Label
var _mascot_timer: Timer
var _mascot_hide_timer: Timer
var _mascot_tween: Tween
var _mascot_idle_tween: Tween
var _mascot_visible: bool = false
var _mascot_head_tex: Texture2D
var _mascot_lion_tex: Texture2D

# Célébration overlay
var _celeb_layer: Control
var _celeb_panel: PanelContainer
var _celeb_title: Label
var _celeb_streak: Label
var _celeb_total: Label
var _celeb_tex: TextureRect
var _celeb_dismiss: Button
var _celeb_share: Button
var _celeb_active: bool = false
var _celeb_sfx: AudioStreamPlayer
var _celeb_sfx_enabled: bool = true
var _deploy_pulse_tween: Tween
var _deploy_scale_tween: Tween
var _night_music_hinted: bool = false
var _deploy_ready_glow: bool = false
var _night_focus: bool = false
var _night_overlay: ColorRect

const MASCOT_W := 100.0
const MASCOT_H_LION := 117.0
const MASCOT_H_HEAD := 88.0
const MASCOT_BUBBLE_W_MIN := 120.0
const MASCOT_BUBBLE_W_MAX := 210.0
const MASCOT_BUBBLE_W := 160.0  # fallback / largeur cible

# Casual / store
const MASCOT_LINES_FR := [
	"Psst… ton build sent bon le thioss 🦁",
	"J’ai vu un preset Android qui m’a fait un clin d’œil.",
	"Si tu déploies, je danse. Si tu ne déploies pas… je danse quand même.",
	"FCFA, ZIP, JWT… mon cerveau tourne en 60 fps.",
	"Le store m’appelle. Ou c’est juste la faim.",
	"Version 1.0.0 ? Courage. Version 1.0.1 ? Légende.",
	"Un clic de trop et je disparaîs dans le baobab numérique.",
	"Modération approuvée = moi content. Sinon je ronronne en boucle.",
	"Tu savais que les lions aussi pushent sur main ?",
	"Chut… j’écoute le serveur. Il a dit « 200 OK ».",
	"Partage WhatsApp = roi de la savane marketing.",
	"Je suis pas un bug. Je suis une feature royale.",
	"Si le upload lag, c’est moi qui traine les pattes. Désolé.",
	"Thiossane c’est nous. Toi, moi, et ce ZIP de 48 Mo.",
]

const MASCOT_LINES_EN := [
	"Psst… your build smells like victory 🦁",
	"An Android preset just winked at me.",
	"If you deploy, I dance. If you don’t… I still dance.",
	"FCFA, ZIP, JWT… my brain runs at 60 fps.",
	"The store is calling. Or maybe it’s lunch.",
	"v1.0.0? Brave. v1.0.1? Legend.",
	"One extra click and I vanish into the digital baobab.",
	"Approved = happy lion. Otherwise I purr in a loop.",
	"Lions push to main too, you know.",
	"Shh… listening to the server. It said « 200 OK ».",
	"WhatsApp share = king of the marketing savanna.",
	"Not a bug. A royal feature.",
	"If upload lags, that’s me dragging my paws. Sorry.",
	"Thiossane is us. You, me, and that 48 MB ZIP.",
]

# Pousse / motivate
const MASCOT_PUSH_FR := [
	"Allez, un petit ship et on se fait une sieste royale.",
	"Ton objectif du jour : finir CE truc. Pas les 47 autres onglets.",
	"Tu es plus proche que tu ne le crois. Clique. Déploie. Respire.",
	"Les grands jeux naissent d’un dev qui n’a pas abandonné à 23 h.",
	"Ce bug te regarde. Toi aussi. Qui cligne en premier ?",
	"Pas parfait ? Tant mieux. Ship d’abord, polish ensuite.",
	"La savane n’attend pas les hésitants. Toi non plus.",
	"Une feature de plus = une fierté de plus. Go.",
	"Tu as déjà survécu à pire que ce warning de compilation.",
	"Objectif clair : une action utile dans les 10 prochaines minutes.",
]

const MASCOT_PUSH_EN := [
	"Come on — one small ship, then a royal nap.",
	"Today’s goal: finish THIS thing. Not the 47 other tabs.",
	"You’re closer than you think. Click. Deploy. Breathe.",
	"Great games come from a dev who didn’t quit at 11 pm.",
	"That bug is staring at you. Stare back. Who blinks first?",
	"Not perfect? Good. Ship first, polish later.",
	"The savanna doesn’t wait for the hesitant. Neither should you.",
	"One more feature = one more win. Go.",
	"You’ve survived worse than this compile warning.",
	"Clear goal: one useful action in the next 10 minutes.",
]

# Se moque / roast
const MASCOT_ROAST_FR := [
	"Encore en train de renommer une variable ? Courage, champion.",
	"Ton TODO list a plus de lignes que ton jeu. Impressionnant.",
	"Je ne juge pas ton code. (Si. Un peu. Beaucoup.)",
	"« Je finis après ce café » — dit le dev… depuis 3 cafés.",
	"Tu debug depuis une heure un truc que tu as codé hier soir. Classique.",
	"Si procrastiner était un preset d’export, tu serais platinum.",
	"Ton « quick fix » a 14 fichiers. On appelle ça un refactor, non ?",
	"La mascotte travaille plus que toi aujourd’hui. Just saying.",
	"Ah, le fameux « je regarde juste Reddit 2 minutes »…",
	"Ton build compile. Ton estime de soi aussi ? Allez, ship.",
]

const MASCOT_ROAST_EN := [
	"Still renaming a variable? Brave of you, champ.",
	"Your TODO list has more lines than your game. Impressive.",
	"I’m not judging your code. (Okay. A little. A lot.)",
	"“After this coffee” — said the dev… three coffees ago.",
	"Debugging for an hour something you wrote last night. Classic.",
	"If procrastination were an export preset, you’d be platinum.",
	"Your “quick fix” touched 14 files. That’s a refactor, friend.",
	"The mascot is working harder than you today. Just saying.",
	"Ah, the classic “I’ll just check Reddit for 2 minutes”…",
	"Your build compiles. Does your confidence? Come on, ship.",
]

# Sens de la vie / objectifs
const MASCOT_WISDOM_FR := [
	"Le sens, c’est souvent : faire un pas, puis le suivant.",
	"Tes objectifs n’ont pas besoin d’être parfaits — juste clairs.",
	"Un petit progrès chaque jour bat une motivation qui n’arrive jamais.",
	"Tu n’es pas en retard. Tu es en chemin.",
	"Ce que tu construis aujourd’hui, quelqu’un y jouera demain.",
	"Repose-toi sans culpabiliser. Un lion fatigué ne chasse pas bien.",
	"Comparer ton chapitre 2 au chapitre 20 d’un autre, c’est injuste.",
	"Les objectifs se mangent en petits morceaux. Comme un baobab… non, un gâteau.",
	"Échouer sur un ship n’efface pas les ships d’avant.",
	"Le vrai flex : tenir promesse envers toi-même, pas envers Twitter.",
]

const MASCOT_WISDOM_EN := [
	"Meaning is often just: take one step, then the next.",
	"Your goals don’t need to be perfect — just clear.",
	"A little progress every day beats motivation that never shows up.",
	"You’re not late. You’re on the path.",
	"What you build today, someone will play tomorrow.",
	"Rest without guilt. A tired lion doesn’t hunt well.",
	"Comparing your chapter 2 to someone else’s chapter 20 is unfair.",
	"Goals are eaten in small bites. Like cake. Not baobabs.",
	"Failing one ship doesn’t erase the ones before.",
	"Real flex: keeping a promise to yourself, not to Twitter.",
]

# Cowboy meme energy (howdy / partner / yeehaw)
const MASCOT_COWBOY_FR := [
	"Howdy partenaire… ce bug-là, c’est pas mon premier rodéo.",
	"Yeehaw ! On ship ou on pleure dans le salon ?",
	"Partner, ce TODO list est plus longue que la route 66.",
	"Dans ce ranch, on compile d’abord, on philosophise après.",
	"Hold my café — je vais dompter ce warning.",
	"Tu gallopes dans 14 branches git. Un vrai cow-boy perdu.",
	"This ain’t a bug, partner… c’est une feature qui porte des bottes.",
	"Le soleil se couche sur ton build. Ship avant la nuit.",
	"Yeehaw, dev ! La savane n’attend pas les tendres.",
	"Partner, ton code sent le campfire et le courage.",
	"Si t’abandonnes maintenant, le shérif (moi) te juge.",
	"Howdy. Objectif du jour : un ship, pas un roman.",
	"Dans le Far West du debug, seul le plus patient gagne.",
	"Yeehaw — encore un commit et on fête au saloon (virtuel).",
	"Partner… ce refactor, c’est une chasse à l’homme. Toi = chasseur.",
	"Les légendes ne pushent pas demain. Elles pushent maintenant.",
	"Howdy mon ami. Respire. Puis clique sur Launch comme un chef.",
	"Ce n’est pas de la procrastination, partner… c’est du « strategic staring ».",
	"Yeehaw ! Même les lions portent le chapeau quand il faut ship.",
	"Partner, le sens de la vie c’est simple : un pas, un ship, une sieste.",
]

const MASCOT_COWBOY_EN := [
	"Howdy partner… this bug ain’t my first rodeo.",
	"Yeehaw! We shipin’ or we cryin’ in the saloon?",
	"Partner, that TODO list is longer than Route 66.",
	"On this ranch we compile first, philosophize later.",
	"Hold my coffee — I’m about to tame that warning.",
	"You’re gallopin’ across 14 git branches. Lost cowboy energy.",
	"This ain’t a bug, partner… it’s a feature wearin’ boots.",
	"Sun’s settin’ on your build. Ship before nightfall.",
	"Yeehaw, dev! The savanna don’t wait for soft hearts.",
	"Partner, your code smells like campfire and grit.",
	"You quit now and the sheriff (me) will judge you.",
	"Howdy. Goal of the day: one ship, not a novel.",
	"In the Far West of debugging, only the patient win.",
	"Yeehaw — one more commit and we celebrate at the (virtual) saloon.",
	"Partner… that refactor is a manhunt. You’re the hunter.",
	"Legends don’t push tomorrow. They push now.",
	"Howdy friend. Breathe. Then hit Launch like a boss.",
	"That ain’t procrastination, partner… it’s strategic starin’.",
	"Yeehaw! Even lions wear the hat when it’s time to ship.",
	"Partner, meaning of life is simple: one step, one ship, one nap.",
]

# Conseils inspirés des grands développeurs du jeu vidéo (paraphrases / esprit)
const MASCOT_DEV_FR := [
	"Miyamoto : un jeu doit se tenir en 30 secondes. Ton intro aussi.",
	"Iwata : un bon producteur protège le temps de l’équipe. Protège le tien.",
	"Carmack : la meilleure optimisation, c’est de ne pas faire le travail inutile.",
	"Sid Meier : un jeu, c’est une série de décisions intéressantes. Et ton code aussi.",
	"Kojima : raconte quelque chose. Même un menu peut avoir une âme.",
	"Will Wright : laisse le joueur créer. Toi, crée l’espace pour ça.",
	"Romero : ship early, ship often… mais teste avant de crier victoire.",
	"Ueda (ICO) : parfois, moins de UI = plus d’émotion.",
	"Suda51 : sois bizarre si ça sert le fun. Le sérieux n’est pas un preset.",
	"Hidetaka Miyazaki : la difficulté peut être juste — jamais gratuite.",
	"Rygiel / GDC vibe : prototype vite, jette vite, garde ce qui fait sourire.",
	"Schafer : l’humour dans un jeu, c’est du design, pas une excuse.",
	"Blow (Braid) : chaque mécanique doit parler aux autres. Sinon, coupe.",
	"Chen (Journey) : l’émotion > le tutoriel. Montre, n’explique pas tout.",
	"Hocking : le joueur comprend mieux en faisant qu’en lisant.",
	"Partner dev tip — Valve : playtest réel > avis de ton ego.",
	"Inafune leçon amère : finis ce que tu commences, ou assume de pivoter.",
	"Yu Suzuki : l’innovation, c’est souvent une vieille idée mieux exécutée.",
	"Miyamoto encore : « Latte » le joueur. Donne-lui une raison de revenir.",
	"Carmack bis : mesure avant d’optimiser. Les feelings mentent, les timers non.",
]

const MASCOT_DEV_EN := [
	"Miyamoto: a game should click in 30 seconds. So should your pitch.",
	"Iwata: a good producer protects the team’s time. Protect yours.",
	"Carmack: the best optimization is not doing useless work.",
	"Sid Meier: a game is a series of interesting decisions. So is your code.",
	"Kojima: tell something. Even a menu can have a soul.",
	"Will Wright: let the player create. You build the space for that.",
	"Romero: ship early, ship often… but test before you celebrate.",
	"Ueda (ICO): sometimes less UI means more emotion.",
	"Suda51: be weird if it serves the fun. Serious isn’t a preset.",
	"Miyazaki: difficulty can be fair — never cheap.",
	"GDC energy: prototype fast, kill fast, keep what makes you smile.",
	"Schafer: humor in a game is design, not an excuse.",
	"Blow (Braid): every mechanic should talk to the others. Else cut it.",
	"Chen (Journey): emotion > tutorial. Show, don’t over-explain.",
	"Hocking: players learn by doing better than by reading.",
	"Partner tip — Valve: real playtests > your ego’s opinion.",
	"Hard lesson: finish what you start, or own the pivot.",
	"Yu Suzuki: innovation is often an old idea executed better.",
	"Miyamoto again: leave the player wanting one more run.",
	"Carmack again: measure before you optimize. Feelings lie, timers don’t.",
]

const MASCOT_WEIRD_FR := [
	"…j’ai mangé un shader par accident.",
	"Ma couronne est un collider. Ne me touche pas trop fort.",
	"Je rêve en PNG 32-bit.",
	"Le void m’a dit bonjour. J’ai dit thioss.",
	"Parfois je tourne à 0.5× juste pour le style.",
]

const MASCOT_WEIRD_EN := [
	"…I ate a shader by accident.",
	"My crown is a collider. Don’t poke too hard.",
	"I dream in 32-bit PNG.",
	"The void said hi. I said thioss.",
	"Sometimes I run at 0.5× just for the vibes.",
]

const MASCOT_SHIP_FR := [
	"Ship it ! La savane t’applaudit 🦁",
	"Build livré. Je danse sur le baobab.",
	"Encore un pour le store. Roi.",
	"ZIP envoyé. Moi content. Toi légende.",
	"Objectif atteint. Tu vois ? C’était possible.",
	"Voilà. Un pas de plus vers ton vrai jeu.",
	"Yeehaw partner ! Build livré. Saloon ouvert.",
	"Howdy — mission accomplie. T’es un vrai cowboy du code.",
]

const MASCOT_SHIP_EN := [
	"Ship it! The savanna applauds 🦁",
	"Build delivered. Dancing on the baobab.",
	"Another one for the store. King.",
	"ZIP sent. Happy lion. Legend you.",
	"Goal hit. See? It was possible.",
	"There. One more step toward your real game.",
	"Yeehaw partner! Build delivered. Saloon’s open.",
	"Howdy — mission done. You’re a real code cowboy.",
]


const MASCOT_LINES_ZH := [
	"嘘…你的构建闻起来像胜利 🦁",
	"一个 Android 预设刚刚对我眨了眨眼。",
	"你部署，我就跳舞。你不部署…我还是跳。",
	"FCFA、ZIP、JWT…我的大脑跑在 60 fps。",
	"商店在叫我。或者只是饿了。",
	"v1.0.0？勇敢。v1.0.1？传奇。",
	"多点一下，我就消失在数字猴面包树里。",
	"审核通过 = 开心的狮子。否则我循环呼噜。",
	"狮子也会 push 到 main，你知道的。",
	"嘘…在听服务器。它说「200 OK」。",
	"WhatsApp 分享 = 营销草原之王。",
	"不是 bug。是皇家功能。",
	"如果上传卡顿，是我在拖爪子。抱歉。",
	"Thiossane 就是我们。你、我，还有那 48 MB 的 ZIP。",
]

const MASCOT_PUSH_ZH := [
	"来吧——一次小小的 ship，然后皇家午睡。",
	"今天的目标：做完这件事。不是另外 47 个标签页。",
	"你比想象中更接近。点。部署。呼吸。",
	"伟大的游戏来自没在晚上 11 点放弃的开发者。",
	"那个 bug 在盯着你。你也盯回去。谁先眨眼？",
	"不完美？很好。先 ship，再打磨。",
	"草原不会等犹豫的人。你也不该。",
	"多一个功能 = 多一份骄傲。上。",
	"你已经熬过比这编译警告更糟的事。",
	"明确目标：接下来 10 分钟做一件有用的事。",
]

const MASCOT_ROAST_ZH := [
	"还在重命名变量？勇敢啊，冠军。",
	"你的 TODO 列表比游戏还长。了不起。",
	"我不评判你的代码。（好吧。有一点。很多。）",
	"「喝完这杯咖啡就做完」——开发者说…已经三杯了。",
	"调试一小时昨晚写的代码。经典。",
	"如果拖延是导出预设，你早就是白金了。",
	"你的「快速修复」动了 14 个文件。那叫重构，朋友。",
	"今天吉祥物比你努力。随便说一句。",
	"啊，经典的「我只看两分钟 Reddit」…",
	"构建编译过了。信心呢？来吧，ship。",
]

const MASCOT_WISDOM_ZH := [
	"意义往往就是：迈一步，再迈一步。",
	"目标不必完美——只要清晰。",
	"每天一点进步，胜过永远不来的动力。",
	"你没有迟到。你在路上。",
	"你今天构建的，明天会有人玩。",
	"休息别内疚。疲惫的狮子猎不好。",
	"拿自己的第 2 章和别人的第 20 章比，不公平。",
	"目标要一小口一小口吃。像蛋糕。",
	"一次 ship 失败抹不掉之前的 ship。",
	"真正的炫耀：对自己守信，不是对 Twitter。",
]

const MASCOT_COWBOY_ZH := [
	"嘿伙伴…这个 bug 不是我第一次参加的牛仔竞技。",
	"Yeehaw！我们是 ship 还是在酒吧哭？",
	"伙伴，那 TODO 列表比 66 号公路还长。",
	"在这个牧场，我们先编译，再谈哲学。",
	"拿着我的咖啡——我要驯服那个警告。",
	"你在 14 个 git 分支上狂奔。迷途牛仔能量。",
	"这不是 bug，伙伴…是穿着靴子的功能。",
	"太阳落在你的构建上。天黑前 ship。",
	"Yeehaw，开发者！草原不等软心肠。",
	"伙伴，你的代码闻起来像篝火和勇气。",
	"现在放弃，警长（我）会审判你。",
	"嘿。今日目标：一次 ship，不是一部小说。",
	"在调试的西部，只有耐心者获胜。",
	"Yeehaw——再提交一次，我们去（虚拟）酒吧庆祝。",
	"伙伴…那次重构是追捕。你是猎人。",
	"传奇不会推到明天。他们现在就推。",
	"嘿朋友。呼吸。然后像老板一样点 Launch。",
	"那不是拖延，伙伴…那是战略性发呆。",
	"Yeehaw！该 ship 时，连狮子都戴帽子。",
	"伙伴，人生意义很简单：一步、一次 ship、一次午睡。",
]

const MASCOT_DEV_ZH := [
	"宫本茂：游戏应在 30 秒内让人上手。你的介绍也一样。",
	"岩田聪：好制作人保护团队时间。也保护你自己的。",
	"卡马克：最好的优化是不做无用功。",
	"席德·梅尔：游戏是一系列有趣决策。你的代码也是。",
	"小岛秀夫：讲点什么。连菜单都可以有灵魂。",
	"威尔·赖特：让玩家创造。你搭建那个空间。",
	"罗梅罗：尽早 ship，经常 ship…但庆祝前先测试。",
	"上田文人（ICO）：有时更少 UI 意味着更多情感。",
	"须田刚一：为好玩可以怪。严肃不是预设。",
	"宫崎英高：难度可以公平——绝不能廉价。",
	"GDC 精神：快速原型，快速淘汰，留下让你微笑的。",
	"谢弗：游戏里的幽默是设计，不是借口。",
	"布洛（Braid）：每个机制应与其他对话。否则砍掉。",
	"陈星汉（Journey）：情感 > 教程。展示，别过度解释。",
	"霍金：玩家在做中学，比阅读更好。",
	"伙伴提示——Valve：真实试玩 > 自我意见。",
	"惨痛教训：做完你开始的，或承担转向。",
	"铃木裕：创新往往是把旧点子执行得更好。",
	"宫本茂再说：让玩家想再来一局。",
	"卡马克再说：优化前先测量。感觉会骗人，计时器不会。",
]

const MASCOT_WEIRD_ZH := [
	"…我不小心吃了一个着色器。",
	"我的皇冠是碰撞体。别戳太重。",
	"我在 32 位 PNG 里做梦。",
	"虚空跟我打招呼。我说 thioss。",
	"有时我以 0.5× 运行，只为氛围。",
]

const MASCOT_SHIP_ZH := [
	"Ship it！草原为你鼓掌 🦁",
	"构建已交付。在猴面包树上跳舞。",
	"又一个上架。王者。",
	"ZIP 已发送。开心狮子。你是传奇。",
	"目标达成。看？是可能的。",
	"好了。向真正游戏又近一步。",
	"Yeehaw 伙伴！构建已交付。酒吧开门。",
	"Howdy——任务完成。你是真正的代码牛仔。",
]




# Pool local Thiossane / teranga / wolof-light — identité Sénégal & Afrique de l’Ouest
const MASCOT_TERANGA_FR := [
	"Teranga d’abord. Ensuite on ship. 🦁",
	"Ndank ndank — un commit, puis le suivant.",
	"Waaw, ce build sent le thioss.",
	"À Dakar comme ici : on avance, on ne regarde pas en arrière.",
	"Le baobab n’a pas poussé en un jour. Ton jeu non plus.",
	"Yalla, on déploie. Incha’Allah le store sourit.",
	"Attaya, puis Deploy. Dans cet ordre… ou l’inverse.",
	"La savane n’attend pas. Toi non plus, champion.",
	"FCFA, ZIP, JWT — le trio du dev thiossane.",
	"WhatsApp le lien, teranga le message. Go.",
	"Modération approuvée = toute la famille fière.",
	"Tu codes pour les joueurs d’ici. Ça se sent.",
	"Un petit ship aujourd’hui, une légende demain.",
	"Le lion ne court pas après chaque gazelle. Choisis ton objectif.",
	"Thiossane c’est nous — toi, moi, et ce preset qui compile enfin.",
	"Pas de stress. Ndank ndank, le serveur suit.",
	"Version 1.0.0 ? Courage. Comme le premier magal du projet.",
	"Si le upload lag, respire. Même le car rapide a des embouteillages.",
	"Roi de la savane = celui qui ship, pas celui qui parle.",
	"Teranga dans le code : accueillant, clair, généreux.",
]

const MASCOT_TERANGA_EN := [
	"Teranga first. Then we ship. 🦁",
	"Ndank ndank — one commit, then the next.",
	"Waaw, this build smells like thioss.",
	"In Dakar like here: we move forward, we don’t look back.",
	"The baobab didn’t grow in a day. Neither did your game.",
	"Yalla, let’s deploy. Insha’Allah the store smiles.",
	"Attaya, then Deploy. In that order… or the other way.",
	"The savanna doesn’t wait. Neither should you, champ.",
	"FCFA, ZIP, JWT — the Thiossane dev trinity.",
	"WhatsApp the link, teranga the message. Go.",
	"Moderation approved = the whole family proud.",
	"You’re coding for players from here. It shows.",
	"One small ship today, a legend tomorrow.",
	"The lion doesn’t chase every gazelle. Pick your goal.",
	"Thiossane is us — you, me, and that preset that finally compiles.",
	"No stress. Ndank ndank, the server will follow.",
	"v1.0.0? Brave. Like the project’s first magal.",
	"If upload lags, breathe. Even the express bus hits traffic.",
	"King of the savanna = the one who ships, not the one who talks.",
	"Teranga in code: welcoming, clear, generous.",
]

const MASCOT_TERANGA_ZH := [
	"先 Teranga，再 ship。🦁",
	"Ndank ndank——一次提交，再下一次。",
	"Waaw，这构建闻起来像 thioss。",
	"在达喀尔和这里一样：往前走，不回头。",
	"猴面包树不是一天长成的。你的游戏也不是。",
	"Yalla，部署吧。Insha’Allah 商店会微笑。",
	"先喝 Attaya，再 Deploy。这个顺序…或者反过来。",
	"草原不等。你也不该等，冠军。",
	"FCFA、ZIP、JWT——Thiossane 开发三件套。",
	"WhatsApp 发链接，Teranga 传心意。上。",
	"审核通过 = 全家人骄傲。",
	"你在为这里的玩家写代码。看得出来。",
	"今天一次小 ship，明天一个传奇。",
	"狮子不追每一只羚羊。选好你的目标。",
	"Thiossane 就是我们——你、我，还有终于能编译的预设。",
	"别紧张。Ndank ndank，服务器会跟上。",
	"v1.0.0？勇敢。像项目的第一次 magal。",
	"上传卡了就呼吸。就算快巴也会堵车。",
	"草原之王 = 真正 ship 的人，不是只会说的人。",
	"代码里的 Teranga：热情、清晰、慷慨。",
]


func _mascot_bubble_width() -> float:
	## Largeur de bulle responsive selon la largeur du dock
	var panel_w := size.x if size.x > 10.0 else 320.0
	# ~52% de la largeur, bornée min/max — lisible même en dock étroit
	var w := clampf(panel_w * 0.52, MASCOT_BUBBLE_W_MIN, MASCOT_BUBBLE_W_MAX)
	return w


func _mascot_apply_bubble_size() -> void:
	if not is_instance_valid(_mascot_bubble) or not is_instance_valid(_mascot_bubble_label):
		return
	var bw := _mascot_bubble_width()
	_mascot_bubble.custom_minimum_size = Vector2(bw, 0)
	_mascot_bubble_label.custom_minimum_size = Vector2(maxf(bw - 24.0, 80.0), 0)
	if is_instance_valid(_mascot_root):
		_mascot_root.custom_minimum_size = Vector2(bw + 8.0, 0)
		_mascot_bubble.reset_size()
		_mascot_root.reset_size()


func _setup_mascot() -> void:
	# Couche flottante au-dessus du scroll — ne clippe pas, ignore la souris sauf sur la mascotte
	_mascot_layer = Control.new()
	_mascot_layer.name = "MascotLayer"
	_mascot_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_mascot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mascot_layer.clip_contents = false
	_mascot_layer.z_index = 100
	add_child(_mascot_layer)

	# Racine : VBox = bulle au-dessus + sprite en dessous (layout stable)
	_mascot_root = VBoxContainer.new()
	_mascot_root.visible = false
	_mascot_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mascot_root.alignment = BoxContainer.ALIGNMENT_CENTER
	_mascot_root.add_theme_constant_override("separation", 6)
	_mascot_root.custom_minimum_size = Vector2(MASCOT_BUBBLE_W + 8, 0)
	_mascot_layer.add_child(_mascot_root)

	# Bulle — style raffiné (ombre soft + bordure or)
	_mascot_bubble = PanelContainer.new()
	_mascot_bubble.visible = false
	_mascot_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mascot_bubble.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bub_sb := StyleBoxFlat.new()
	bub_sb.bg_color = Color(0.16, 0.17, 0.20, 0.96)
	bub_sb.set_corner_radius_all(14)
	bub_sb.content_margin_left = 12
	bub_sb.content_margin_right = 12
	bub_sb.content_margin_top = 10
	bub_sb.content_margin_bottom = 10
	bub_sb.border_width_left = 1
	bub_sb.border_width_right = 1
	bub_sb.border_width_top = 1
	bub_sb.border_width_bottom = 1
	bub_sb.border_color = Color(C_PRIMARY.r, C_PRIMARY.g, C_PRIMARY.b, 0.85)
	bub_sb.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	bub_sb.shadow_size = 6
	bub_sb.shadow_offset = Vector2(0, 3)
	bub_sb.anti_aliasing = true
	_mascot_bubble.add_theme_stylebox_override("panel", bub_sb)
	_mascot_bubble.custom_minimum_size = Vector2(MASCOT_BUBBLE_W, 0)
	_mascot_root.add_child(_mascot_bubble)

	_mascot_bubble_label = Label.new()
	_mascot_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mascot_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mascot_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mascot_bubble_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mascot_bubble_label.custom_minimum_size = Vector2(MASCOT_BUBBLE_W - 24, 0)
	_mascot_bubble_label.add_theme_font_size_override("font_size", _ed_font(-1))
	_mascot_bubble_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.88))
	_mascot_bubble.add_child(_mascot_bubble_label)

	# Sprite + tenue thématique (verres, campagne, disco…)
	_mascot_sprite_box = Control.new()
	_mascot_sprite_box.custom_minimum_size = Vector2(MASCOT_W, MASCOT_H_LION)
	_mascot_sprite_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mascot_sprite_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_mascot_sprite_box.gui_input.connect(_on_mascot_gui_input)
	_mascot_root.add_child(_mascot_sprite_box)

	_mascot_tex = TextureRect.new()
	_mascot_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mascot_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mascot_tex.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_mascot_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mascot_sprite_box.add_child(_mascot_tex)

	_mascot_outfit = Control.new()
	_mascot_outfit.name = "MascotOutfit"
	_mascot_outfit.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_mascot_outfit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mascot_sprite_box.add_child(_mascot_outfit)

	_load_mascot_textures()
	_setup_celebration_ui()

	_mascot_timer = Timer.new()
	_mascot_timer.one_shot = true
	_mascot_timer.timeout.connect(_on_mascot_spawn_tick)
	add_child(_mascot_timer)

	_mascot_hide_timer = Timer.new()
	_mascot_hide_timer.one_shot = true
	_mascot_hide_timer.timeout.connect(_mascot_hide)
	add_child(_mascot_hide_timer)

	_mascot_schedule_next(25.0, 50.0)


func _load_mascot_textures() -> void:
	var base := "res://addons/thiossane_deploy/"
	var head_path := base + "mascot_head.png"
	var lion_path := base + "mascot_lion.png"
	if ResourceLoader.exists(head_path):
		_mascot_head_tex = load(head_path) as Texture2D
	if ResourceLoader.exists(lion_path):
		_mascot_lion_tex = load(lion_path) as Texture2D
	if _mascot_lion_tex == null or _mascot_head_tex == null:
		var script_path := ""
		if get_script():
			script_path = get_script().resource_path.get_base_dir()
		if _mascot_lion_tex == null:
			var img := Image.new()
			for p in [lion_path, script_path.path_join("mascot_lion.png")]:
				if p == "" or not FileAccess.file_exists(p):
					continue
				if img.load(p) == OK:
					_mascot_lion_tex = ImageTexture.create_from_image(img)
					break
		if _mascot_head_tex == null:
			var img2 := Image.new()
			for p in [head_path, script_path.path_join("mascot_head.png")]:
				if p == "" or not FileAccess.file_exists(p):
					continue
				if img2.load(p) == OK:
					_mascot_head_tex = ImageTexture.create_from_image(img2)
					break
	if _mascot_lion_tex:
		_mascot_tex.texture = _mascot_lion_tex
	elif _mascot_head_tex:
		_mascot_tex.texture = _mascot_head_tex


func _mascot_schedule_next(min_s: float = 45.0, max_s: float = 140.0) -> void:
	if not is_instance_valid(_mascot_timer):
		return
	_mascot_timer.start(randf_range(min_s, max_s))


func _on_mascot_spawn_tick() -> void:
	if not is_inside_tree() or _celeb_active:
		_mascot_schedule_next(20.0, 40.0)
		return
	if is_busy and randf() < 0.55:
		_mascot_schedule_next(20.0, 40.0)
		return
	_mascot_show()



func _mascot_lang_bag(fr_bag: Array, en_bag: Array, zh_bag: Array) -> Array:
	## Sélectionne le tableau de répliques selon la langue UI active (fr / en / zh).
	match _lang:
		"en":
			return en_bag
		"zh":
			return zh_bag
		_:
			return fr_bag


func _mascot_pick_line(force_ship: bool = false) -> String:
	## Toujours respecter la langue UI active (_lang : "fr" | "en" | "zh").
	## Mix : teranga (identité Thiossane), cowboy, devs, push, roast, wisdom, casual, weird.
	## Thèmes AF (teranga/wax/sahel/savane) → biais fort vers le pool local.
	if _ui_theme == "matrix" and randf() < 0.72:
		return _mascot_scifi_line(force_ship)
	if force_ship:
		# Ship réussi : sur thèmes AF, teinte teranga une fois sur deux
		if _ui_theme in ["teranga", "wax", "sahel", "savane"] and randf() < 0.55:
			var tbag: Array = _mascot_lang_bag(MASCOT_TERANGA_FR, MASCOT_TERANGA_EN, MASCOT_TERANGA_ZH)
			return tbag[randi() % tbag.size()]
		var bag: Array = _mascot_lang_bag(MASCOT_SHIP_FR, MASCOT_SHIP_EN, MASCOT_SHIP_ZH)
		return bag[randi() % bag.size()]
	# Bias thèmes Afrique de l’Ouest — identité Thiossane (fort)
	if _ui_theme in ["teranga", "wax", "sahel", "savane"] and randf() < 0.78:
		var teranga: Array = _mascot_lang_bag(MASCOT_TERANGA_FR, MASCOT_TERANGA_EN, MASCOT_TERANGA_ZH)
		return teranga[randi() % teranga.size()]
	# Bias western / chicago — cowboy
	if _ui_theme in ["western", "chicago30"] and randf() < 0.55:
		var cowboy: Array = _mascot_lang_bag(MASCOT_COWBOY_FR, MASCOT_COWBOY_EN, MASCOT_COWBOY_ZH)
		return cowboy[randi() % cowboy.size()]
	if _ui_theme in ["horror", "underground"] and randf() < 0.50:
		var weird: Array = _mascot_lang_bag(MASCOT_WEIRD_FR, MASCOT_WEIRD_EN, MASCOT_WEIRD_ZH)
		return weird[randi() % weird.size()]
	if _ui_theme in ["pixel", "ps2"] and randf() < 0.40:
		var dev: Array = _mascot_lang_bag(MASCOT_DEV_FR, MASCOT_DEV_EN, MASCOT_DEV_ZH)
		return dev[randi() % dev.size()]
	var r := randf()
	var bag: Array
	if r < 0.20:
		# Identité Thiossane présente même hors thèmes AF
		bag = _mascot_lang_bag(MASCOT_TERANGA_FR, MASCOT_TERANGA_EN, MASCOT_TERANGA_ZH)
	elif r < 0.34:
		bag = _mascot_lang_bag(MASCOT_COWBOY_FR, MASCOT_COWBOY_EN, MASCOT_COWBOY_ZH)
	elif r < 0.50:
		# Grands développeurs du jeu vidéo
		bag = _mascot_lang_bag(MASCOT_DEV_FR, MASCOT_DEV_EN, MASCOT_DEV_ZH)
	elif r < 0.60:
		bag = _mascot_lang_bag(MASCOT_PUSH_FR, MASCOT_PUSH_EN, MASCOT_PUSH_ZH)
	elif r < 0.68:
		bag = _mascot_lang_bag(MASCOT_ROAST_FR, MASCOT_ROAST_EN, MASCOT_ROAST_ZH)
	elif r < 0.78:
		bag = _mascot_lang_bag(MASCOT_WISDOM_FR, MASCOT_WISDOM_EN, MASCOT_WISDOM_ZH)
	elif r < 0.86:
		bag = _mascot_lang_bag(MASCOT_WEIRD_FR, MASCOT_WEIRD_EN, MASCOT_WEIRD_ZH)
	else:
		bag = _mascot_lang_bag(MASCOT_LINES_FR, MASCOT_LINES_EN, MASCOT_LINES_ZH)
	return bag[randi() % bag.size()]


func _mascot_scifi_line(force_ship: bool = false) -> String:
	if force_ship:
		var ship_fr := [
			"TERMINATED. Ship réussi. *click*",
			"Hasta la vista, bugs. Build en ligne.",
			"I'll be back… avec le prochain hotfix.",
			"Cible éliminée. Store acquis.",
			"Wake up, Neo… ton jeu est live.",
		]
		var ship_en := [
			"TERMINATED. Ship successful. *click*",
			"Hasta la vista, bugs. Build is live.",
			"I'll be back… with the next hotfix.",
			"Target eliminated. Store acquired.",
			"Wake up, Neo… your game is live.",
		]
		var ship_zh := [
			"TERMINATED. Ship 成功。*click*",
			"Hasta la vista，bugs。构建已上线。",
			"I'll be back…带着下一个热修复。",
			"目标已消灭。商店已夺取。",
			"醒来吧，Neo…你的游戏已上线。",
		]
		var ship_bag: Array = _mascot_lang_bag(ship_fr, ship_en, ship_zh)
		return ship_bag[randi() % ship_bag.size()]
	var fr := [
		"*click-click* Chasseur en approche. Déploie avant qu’il te trouve.",
		"CIBLE ACQUISE. Ce ZIP a une signature thermique… intéressante.",
		"Come with me if you want to live — et shipper.",
		"Il n’y a pas de cuillère. Il y a un bouton Deploy.",
		"System online. Prêt à terminer… euh, déployer.",
		"Predator mode : invisible aux bugs, mortel pour les presets manquants.",
		"I'll be back. Après ce café. Peut-être.",
		"ꖌꖎꖒ *click* — traduction : « ship maintenant ».",
		"Hasta la vista, procrastination.",
		"Matrix has you… mais le store t’attend.",
		"Thermal vision : 3 TODO, 1 bug critique, 0 excuse.",
		"Yautja proverb : un bon build ne laisse pas de traces… sauf un lien store.",
	]
	var en_lines := [
		"*click-click* Hunter inbound. Deploy before it finds you.",
		"TARGET ACQUIRED. That ZIP has an… interesting heat signature.",
		"Come with me if you want to live — and ship.",
		"There is no spoon. There is a Deploy button.",
		"System online. Ready to terminate… uh, deploy.",
		"Predator mode: invisible to bugs, lethal to missing presets.",
		"I'll be back. After this coffee. Maybe.",
		"ꖌꖎꖒ *click* — translation: “ship now”.",
		"Hasta la vista, procrastination.",
		"Matrix has you… but the store is waiting.",
		"Thermal vision: 3 TODOs, 1 critical bug, 0 excuses.",
		"Yautja proverb: a good build leaves no traces… except a store link.",
	]
	var zh_lines := [
		"*click-click* 猎人接近中。在他找到你之前部署。",
		"目标已锁定。这个 ZIP 有…有趣的热信号。",
		"跟我来如果你想活——并且 ship。",
		"没有勺子。只有 Deploy 按钮。",
		"系统在线。准备终结…呃，部署。",
		"掠食者模式：对 bug 隐形，对缺失预设致命。",
		"I'll be back。喝完这杯咖啡。也许。",
		"ꖌꖎꖒ *click* — 翻译：「现在就 ship」。",
		"Hasta la vista，拖延。",
		"Matrix 控制着你…但商店在等你。",
		"热成像：3 个 TODO，1 个关键 bug，0 个借口。",
		"Yautja 谚语：好的构建不留痕迹…除了商店链接。",
	]
	var bag: Array = _mascot_lang_bag(fr, en_lines, zh_lines)
	return bag[randi() % bag.size()]


func _mascot_apply_sprite(use_head: bool = false) -> void:
	var sz := Vector2(MASCOT_W, MASCOT_H_LION)
	if use_head and _mascot_head_tex:
		_mascot_tex.texture = _mascot_head_tex
		sz = Vector2(MASCOT_H_HEAD, MASCOT_H_HEAD)
	elif _mascot_lion_tex:
		_mascot_tex.texture = _mascot_lion_tex
		sz = Vector2(MASCOT_W, MASCOT_H_LION)
	elif _mascot_head_tex:
		_mascot_tex.texture = _mascot_head_tex
		sz = Vector2(MASCOT_H_HEAD, MASCOT_H_HEAD)
	if is_instance_valid(_mascot_sprite_box):
		_mascot_sprite_box.custom_minimum_size = sz
	_mascot_rebuild_outfit()


func _mascot_bottom_right() -> Vector2:
	# Toujours coin bas-droit du dock — prévisible, ne recouvre pas les champs du haut
	var panel_w := size.x if size.x > 10.0 else 320.0
	var panel_h := size.y if size.y > 10.0 else 600.0
	_mascot_apply_bubble_size()
	_mascot_root.reset_size()
	var min_sz := _mascot_root.get_combined_minimum_size()
	var bw := _mascot_bubble_width()
	var rw := maxf(min_sz.x, bw + 8.0)
	var rh := maxf(min_sz.y, MASCOT_H_LION + 48.0)
	var x := clampf(panel_w - rw - 8.0, 4.0, maxf(panel_w - 36.0, 4.0))
	var y := clampf(panel_h - rh - 10.0, 36.0, maxf(panel_h - 36.0, 36.0))
	return Vector2(x, y)


func _mascot_stop_idle() -> void:
	if _mascot_idle_tween and _mascot_idle_tween.is_valid():
		_mascot_idle_tween.kill()
	_mascot_idle_tween = null


func _mascot_start_idle() -> void:
	## Flottement doux en boucle tant que la mascotte est visible
	if not _mascot_visible or not is_instance_valid(_mascot_root):
		return
	_mascot_stop_idle()
	var base_y := _mascot_root.position.y
	_mascot_idle_tween = create_tween()
	_mascot_idle_tween.set_loops()
	_mascot_idle_tween.tween_property(_mascot_root, "position:y", base_y - 5.0, 1.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_mascot_idle_tween.tween_property(_mascot_root, "position:y", base_y + 3.0, 1.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _mascot_show(force_ship_line: bool = false) -> void:
	if not is_instance_valid(_mascot_root) or not is_instance_valid(_mascot_layer):
		return
	if _mascot_visible or _celeb_active:
		return
	_mascot_visible = true
	_mascot_stop_idle()

	var use_head := _mascot_head_tex != null and _mascot_lion_tex != null and randf() < 0.30 and not force_ship_line
	_mascot_apply_sprite(use_head)

	_mascot_apply_bubble_size()
	_mascot_bubble_label.text = _mascot_pick_line(force_ship_line)
	_mascot_bubble.visible = true
	_mascot_root.reset_size()

	var target := _mascot_bottom_right()
	var start := target + Vector2(12, 48)
	_mascot_root.position = start
	_mascot_root.modulate = Color(1, 1, 1, 0)
	_mascot_root.rotation_degrees = randf_range(-6.0, 6.0)
	_mascot_root.scale = Vector2(0.72, 0.72)
	var piv := _mascot_root.get_combined_minimum_size() * 0.5
	_mascot_root.pivot_offset = piv
	_mascot_root.visible = true

	if _mascot_tween and _mascot_tween.is_valid():
		_mascot_tween.kill()
	_mascot_tween = create_tween()
	_mascot_tween.set_parallel(true)
	# Entrée fluide : slide + fade + soft overshoot
	_mascot_tween.tween_property(_mascot_root, "position", target, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_mascot_tween.tween_property(_mascot_root, "modulate:a", 1.0, 0.28)
	_mascot_tween.tween_property(_mascot_root, "rotation_degrees", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_mascot_tween.tween_property(_mascot_root, "scale", Vector2(1.04, 1.04), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_mascot_tween.chain().tween_property(_mascot_root, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_mascot_tween.chain().tween_callback(func():
		_mascot_do_weird_move()
		_mascot_start_idle()
	)

	_mascot_hide_timer.start(randf_range(6.0, 10.0))


func _mascot_do_weird_move() -> void:
	if not _mascot_visible or not is_instance_valid(_mascot_root):
		return
	# Pause idle pendant le gag, puis reprise
	_mascot_stop_idle()
	var t := create_tween()
	var act := randi() % 5
	match act:
		0:  # wiggle doux
			t.tween_property(_mascot_root, "rotation_degrees", 5.0, 0.12).set_trans(Tween.TRANS_SINE)
			t.tween_property(_mascot_root, "rotation_degrees", -5.0, 0.14).set_trans(Tween.TRANS_SINE)
			t.tween_property(_mascot_root, "rotation_degrees", 0.0, 0.12).set_trans(Tween.TRANS_SINE)
		1:  # squash & stretch
			t.tween_property(_mascot_root, "scale", Vector2(1.08, 0.92), 0.1).set_trans(Tween.TRANS_QUAD)
			t.tween_property(_mascot_root, "scale", Vector2(0.94, 1.06), 0.12).set_trans(Tween.TRANS_QUAD)
			t.tween_property(_mascot_root, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK)
		2:  # petit hop
			var y0 := _mascot_root.position.y
			t.tween_property(_mascot_root, "position:y", y0 - 16.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t.tween_property(_mascot_root, "position:y", y0, 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		3:  # clin d'œil (scale X)
			t.tween_property(_mascot_root, "scale:x", 0.88, 0.08)
			t.tween_property(_mascot_root, "scale:x", 1.0, 0.12).set_trans(Tween.TRANS_BACK)
		_:  # hochement
			t.tween_property(_mascot_root, "rotation_degrees", 8.0, 0.14).set_trans(Tween.TRANS_SINE)
			t.tween_property(_mascot_root, "rotation_degrees", 0.0, 0.22).set_trans(Tween.TRANS_BACK)
	t.chain().tween_callback(_mascot_start_idle)


func _mascot_hide() -> void:
	if not _mascot_visible or not is_instance_valid(_mascot_root):
		_mascot_schedule_next()
		return
	_mascot_stop_idle()
	if _mascot_tween and _mascot_tween.is_valid():
		_mascot_tween.kill()
	_mascot_tween = create_tween()
	_mascot_tween.set_parallel(true)
	var exit := _mascot_root.position + Vector2(8, 50)
	_mascot_tween.tween_property(_mascot_root, "position", exit, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_mascot_tween.tween_property(_mascot_root, "modulate:a", 0.0, 0.32)
	_mascot_tween.tween_property(_mascot_root, "scale", Vector2(0.55, 0.55), 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_mascot_tween.tween_property(_mascot_root, "rotation_degrees", randf_range(-4.0, 4.0), 0.35)
	_mascot_tween.chain().tween_callback(func():
		if is_instance_valid(_mascot_root):
			_mascot_root.visible = false
			_mascot_bubble.visible = false
			_mascot_root.rotation_degrees = 0.0
			_mascot_root.scale = Vector2.ONE
		_mascot_visible = false
		_mascot_schedule_next()
	)


func _on_mascot_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _mascot_visible:
		return
	_mascot_apply_bubble_size()
	_mascot_bubble_label.text = _mascot_pick_line()
	_mascot_bubble.reset_size()
	_mascot_root.reset_size()
	# Recale en bas-droite si la bulle a grossi
	_mascot_root.position = _mascot_bottom_right()
	_mascot_do_weird_move()
	if is_instance_valid(_mascot_hide_timer):
		_mascot_hide_timer.stop()
		_mascot_hide_timer.start(randf_range(4.0, 7.0))


# ── Streak + célébration ─────────────────────────────────────────────────────

func _ship_week_key_now() -> String:
	var t := Time.get_datetime_dict_from_system()
	# Semaine approximative ISO-like : année + jour de l'année / 7
	var day_of_year := 0
	var days_in_month := [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var y: int = int(t["year"])
	if (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0):
		days_in_month[2] = 29
	for m in range(1, int(t["month"])):
		day_of_year += days_in_month[m]
	day_of_year += int(t["day"])
	var week := int(ceil(float(day_of_year) / 7.0))
	return "%d-W%02d" % [y, week]


func _ship_ensure_week() -> void:
	var key := _ship_week_key_now()
	if _ship_week_key != key:
		_ship_week_key = key
		_ship_week_count = 0


func _on_ship_success() -> void:
	_ship_ensure_week()
	_ship_total += 1
	_ship_week_count += 1
	_record_deploy_history("ok")
	_save_config()
	# Notification desktop — le dev a souvent changé d’onglet
	_notify_desktop(
		tr_ui("notify_ship_title"),
		_fmt("notify_ship_body", [
			title_edit.text.strip_edges() if is_instance_valid(title_edit) else "game",
			_deploy_version if _deploy_version != "" else "?"
		])
	)
	# Masquer la mascotte random si présente
	if _mascot_visible:
		_mascot_hide_timer.stop()
		_mascot_stop_idle()
		if _mascot_tween and _mascot_tween.is_valid():
			_mascot_tween.kill()
		if is_instance_valid(_mascot_root):
			_mascot_root.visible = false
			_mascot_bubble.visible = false
		_mascot_visible = false
	# FX immersif auto — l’impact du ship, pas un bouton à cliquer
	_workflow_fx_ship_success()
	_celebrate_ship()


func _record_deploy_history(result: String) -> void:
	var plats: PackedStringArray = []
	if is_instance_valid(platform_web) and platform_web.button_pressed:
		plats.append("web")
	if is_instance_valid(platform_windows) and platform_windows.button_pressed:
		plats.append("windows")
	if is_instance_valid(platform_android) and platform_android.button_pressed:
		plats.append("android")
	var entry := {
		"ts": Time.get_datetime_string_from_system(),
		"game_id": selected_game_id,
		"title": title_edit.text.strip_edges() if is_instance_valid(title_edit) else "",
		"version": _deploy_version if _deploy_version != "" else (version_edit.text.strip_edges() if is_instance_valid(version_edit) else ""),
		"platforms": ",".join(plats),
		"status": selected_game_status,
		"result": result,
	}
	_deploy_history.push_front(entry)
	while _deploy_history.size() > DEPLOY_HISTORY_MAX:
		_deploy_history.pop_back()
	_refresh_hist_list()


func _refresh_hist_list() -> void:
	if not is_instance_valid(_hist_list):
		return
	_hist_list.clear()
	for e in _deploy_history:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var icon := "✔" if str(e.get("result", "")) == "ok" else "✖"
		var line := "%s %s · %s v%s · %s" % [
			icon,
			str(e.get("ts", "")).substr(0, 16),
			str(e.get("title", "?")).substr(0, 22),
			str(e.get("version", "?")),
			str(e.get("platforms", "")),
		]
		_hist_list.add_item(line)


func _notify_desktop(title: String, body: String) -> void:
	## Notification OS + attention fenêtre éditeur.
	# 1) Attirer l’attention de la fenêtre Godot
	if DisplayServer.has_method("window_request_attention"):
		DisplayServer.window_request_attention()
	# 2) Linux notify-send (si dispo)
	if OS.get_name() == "Linux":
		var args := PackedStringArray(["-u", "normal", "-a", "Thiossane Deploy", title, body])
		OS.execute("notify-send", args, [], false, false)
	elif OS.get_name() == "Windows":
		# PowerShell balloon léger (best-effort)
		var ps := "Add-Type -AssemblyName System.Windows.Forms; $n = New-Object System.Windows.Forms.NotifyIcon; $n.Icon = [System.Drawing.SystemIcons]::Information; $n.Visible = $true; $n.ShowBalloonTip(4000, '%s', '%s', [System.Windows.Forms.ToolTipIcon]::Info)" % [
			title.replace("'", ""), body.replace("'", "")
		]
		OS.execute("powershell", PackedStringArray(["-NoProfile", "-Command", ps]), [], false, false)
	elif OS.get_name() == "macOS":
		var script := "display notification \"%s\" with title \"%s\"" % [
			body.replace("\"", "\\\""), title.replace("\"", "\\\"")
		]
		OS.execute("osascript", PackedStringArray(["-e", script]), [], false, false)
	_log("🔔 " + title + " — " + body, "ok")


func _game_public_url() -> String:
	if selected_game_id < 1:
		return ""
	# Préférer lien tracké si dispo
	if not _current_share.is_empty():
		var path := str(_current_share.get("path", "")).strip_edges()
		if path != "":
			return _full_share_url(path)
	return _store_base() + "game.html?id=%d" % selected_game_id




# ══════════════════════════════════════════════════════════════════════════════
# AMBASSADEURS (API POST /developer/games/{id}/ambassador-links + stats)
# ══════════════════════════════════════════════════════════════════════════════

func _clear_ambassador_ui() -> void:
	_current_ambassador = {}
	if is_instance_valid(amb_url_edit):
		amb_url_edit.text = ""
		amb_url_edit.placeholder_text = tr_ui("amb_empty")
	if is_instance_valid(amb_stats_label):
		amb_stats_label.text = tr_ui("amb_stats_line") % [0, 0, 0, 0]


func _on_ambassador_generate_pressed() -> void:
	if is_busy:
		return
	if access_token == "":
		_feedback(tr_ui("connect_first"), "warn")
		return
	if selected_game_id < 1:
		_feedback(tr_ui("share_need_game"), "warn")
		return
	var email := ""
	if is_instance_valid(amb_email_edit):
		email = amb_email_edit.text.strip_edges()
	if not _ShareApi.is_valid_email(email):
		_feedback(tr_ui("amb_need_email"), "warn")
		return
	var label := ""
	if is_instance_valid(amb_label_edit):
		label = amb_label_edit.text.strip_edges()
	var send_invite := false
	if is_instance_valid(amb_invite_check):
		send_invite = amb_invite_check.button_pressed

	var body: Dictionary = _ShareApi.ambassador_create_body(email, label, "", send_invite)
	_set_busy(true)
	_log("Création lien ambassadeur jeu #%d → %s" % [selected_game_id, email])
	_request_json(
		HTTPClient.METHOD_POST,
		_ShareApi.ambassador_create_path(selected_game_id),
		body,
		ReqKind.AMBASSADOR_CREATE
	)


func _handle_ambassador_create(code: int, data: Variant) -> void:
	_set_busy(false)
	if code >= 200 and code < 300 and typeof(data) == TYPE_DICTIONARY:
		_current_ambassador = data
		var path := str(data.get("path", ""))
		var url: String = _ShareApi.full_store_url(_store_base(), path)
		if is_instance_valid(amb_url_edit):
			amb_url_edit.text = url
		var clicks := int(data.get("clicks", 0))
		var uniq := int(data.get("unique_clicks", 0))
		var conv := int(data.get("conversions", 0))
		var status := str(data.get("status", ""))
		if is_instance_valid(amb_stats_label):
			amb_stats_label.text = tr_ui("amb_link_line") % [status, clicks, uniq, conv]
		_log("Ambassador OK token=%s status=%s email=%s" % [
			str(data.get("token", "")), status, str(data.get("ambassador_email", ""))
		])
		var msg := tr_ui("amb_ok")
		if data.get("reused", false):
			msg = tr_ui("amb_reused")
		if data.get("user_exists") == false:
			msg += " " + tr_ui("amb_pending_user")
		_feedback(msg, "ok")
		_save_config()
	else:
		var err := _api_error_message(data, code)
		_log("Ambassador HTTP %d: %s" % [code, err])
		_feedback(tr_ui("amb_fail") % err, "err")


func _on_ambassador_stats_pressed() -> void:
	if is_busy:
		return
	if access_token == "":
		_feedback(tr_ui("connect_first"), "warn")
		return
	_set_busy(true)
	_request_json(
		HTTPClient.METHOD_GET,
		_ShareApi.ambassador_stats_path(),
		{},
		ReqKind.AMBASSADOR_STATS
	)


func _handle_ambassador_stats(code: int, data: Variant) -> void:
	_set_busy(false)
	if code >= 200 and code < 300 and typeof(data) == TYPE_DICTIONARY:
		var links := int(data.get("total_links", 0))
		var clicks := int(data.get("total_clicks", 0))
		var uniq := int(data.get("total_unique_clicks", 0))
		var conv := int(data.get("total_conversions", 0))
		if is_instance_valid(amb_stats_label):
			amb_stats_label.text = tr_ui("amb_stats_line") % [links, clicks, uniq, conv]
		_log("Ambassador stats: %s" % _ShareApi.summarize_ambassador_stats(data))
		_feedback(tr_ui("amb_stats_ok") % [links, clicks, conv], "ok")
	else:
		var err := _api_error_message(data, code)
		_log("Ambassador stats HTTP %d: %s" % [code, err])
		_feedback(tr_ui("amb_fail") % err, "err")


func _handle_ambassador_list(code: int, data: Variant) -> void:
	_set_busy(false)
	if code >= 200 and code < 300 and typeof(data) == TYPE_DICTIONARY:
		var items = data.get("items", [])
		var n: int = items.size() if typeof(items) == TYPE_ARRAY else 0
		_log("Ambassador list: %d liens" % n)
		_feedback(tr_ui("amb_list_ok") % n, "ok")
	else:
		var err := _api_error_message(data, code)
		_feedback(tr_ui("amb_fail") % err, "err")


func _handle_ambassador_revoke(code: int, data: Variant) -> void:
	_set_busy(false)
	if code >= 200 and code < 300:
		_log("Ambassador link révoqué")
		_feedback(tr_ui("amb_revoked"), "ok")
		_clear_ambassador_ui()
	else:
		var err := _api_error_message(data, code)
		_feedback(tr_ui("amb_fail") % err, "err")


func _on_ambassador_copy() -> void:
	var url := ""
	if is_instance_valid(amb_url_edit):
		url = amb_url_edit.text.strip_edges()
	if url == "":
		_feedback(tr_ui("amb_empty"), "warn")
		return
	DisplayServer.clipboard_set(url)
	_feedback(tr_ui("share_copied"), "ok")


func _game_title_for_share() -> String:
	if is_instance_valid(title_edit) and title_edit.text.strip_edges() != "":
		return title_edit.text.strip_edges()
	for g in my_games:
		if int(g.get("id", -1)) == selected_game_id:
			return str(g.get("title", "Mon jeu"))
	return "Mon jeu"


func _on_copy_store_page() -> void:
	var url := _game_public_url()
	if url == "":
		_feedback(tr_ui("share_need_game"), "warn")
		return
	DisplayServer.clipboard_set(url)
	_feedback(tr_ui("link_copied"), "ok")
	_log("Lien store: " + url)


func _on_copy_discord_blurb() -> void:
	var url := _game_public_url()
	if url == "":
		_feedback(tr_ui("share_need_game"), "warn")
		return
	var title := _game_title_for_share()
	var msg := _fmt("link_discord_msg", [title, url])
	DisplayServer.clipboard_set(msg)
	_feedback(tr_ui("link_copied"), "ok")


func _on_copy_whatsapp_blurb() -> void:
	var url := _game_public_url()
	if url == "":
		_feedback(tr_ui("share_need_game"), "warn")
		return
	var title := _game_title_for_share()
	var msg := _fmt("link_whatsapp_msg", [title, url])
	DisplayServer.clipboard_set(msg)
	_feedback(tr_ui("link_copied"), "ok")


## FX liés au workflow (auto, immersifs, fun).
## kind: "login" | "fiche" | "deploy_start" | "export" | "upload" | "ship" | "fail" | "milestone"
func _workflow_fx(kind: String) -> void:
	if not is_inside_tree():
		return
	match kind:
		"login":
			_wf_pulse_banner(C_OK)
			_wf_sparkle_burst(C_PRIMARY, 12)
		"fiche":
			_wf_pulse_banner(C_PRIMARY)
			_wf_sparkle_burst(C_ACCENT, 8)
		"deploy_start":
			_wf_deploy_ignition()
		"export":
			_wf_progress_glow()
		"upload":
			_wf_upload_energy()
		"ship":
			_workflow_fx_ship_success()
		"fail":
			_wf_fail_shake()
		"milestone":
			_workflow_fx_ship_success(true)


func _workflow_fx_ship_success(epic: bool = false) -> void:
	## Célébration auto selon thème + jalons. Pas de clic requis.
	if _chaos_active:
		return
	var milestone := _ship_total in [1, 5, 10, 25, 50, 100] or epic
	# Intensité soft pour le flow pro, plus fort sur jalons
	var prev_int := _chaos_intensity
	var prev_dur := _chaos_duration_mult
	var prev_auto := _chaos_auto_restore
	_chaos_intensity = 1.35 if milestone else 0.9
	_chaos_duration_mult = 1.15 if milestone else 0.75
	_chaos_auto_restore = true
	var kind := _wf_pick_success_fx()
	# Lancer après un court délai pour laisser la carte célébration apparaître
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		if not is_inside_tree():
			return
		if not _chaos_active:
			_chaos_start(kind)
		_chaos_intensity = prev_int
		_chaos_duration_mult = prev_dur
		_chaos_auto_restore = prev_auto
	)
	# Floating impact text
	get_tree().create_timer(0.15).timeout.connect(func() -> void:
		if not is_inside_tree() or not is_instance_valid(_celeb_layer):
			return
		_wf_impact_title(milestone)
	)


func _wf_pick_success_fx() -> String:
	match _ui_theme:
		"matrix":
			return "matrix"
		"ps2", "pixel":
			return "matrix" if randf() < 0.5 else "explode"
		"underground", "gangster90", "horror":
			return "terminator" if randf() < 0.55 else "burn"
		"chicago30", "steampunk":
			return "explode"
		"gangsta00", "vaporwave":
			return "explode" if randf() < 0.5 else "terminator"
		"ember", "sunrise", "teranga", "wax", "sahel", "savane":
			return "burn" if randf() < 0.5 else "explode"
		"onyx", "circe", "custom", "default", "minimal":
			return "explode" if randf() < 0.55 else "terminator"
		"forest":
			return "explode"
		"sakura", "ivory", "sepia":
			return "explode"
		"synthwave", "cyberpunk":
			return "matrix" if randf() < 0.4 else "explode"
		"manga", "comicbook":
			return "explode" if randf() < 0.6 else "terminator"
		"ocean":
			return "explode"
		"brutalist":
			return "terminator" if randf() < 0.5 else "explode"
		"western":
			return "burn" if randf() < 0.55 else "explode"
		_:
			return "explode"


func _wf_impact_title(milestone: bool = false) -> void:
	if not is_instance_valid(_celeb_layer) and not is_instance_valid(self):
		return
	var parent: Control = _celeb_layer if is_instance_valid(_celeb_layer) else self
	var lbl := Label.new()
	if milestone:
		lbl.text = _fmt("wf_milestone", _ship_total)
	else:
		var lines_fr := ["IMPACT DÉPLOYÉ", "SHIP RÉUSSI", "EN LIGNE 🚀", "MISSION ACCOMPLIE"]
		var lines_en := ["IMPACT DEPLOYED", "SHIP SUCCESS", "LIVE 🚀", "MISSION COMPLETE"]
		var lines_zh := ["冲击已部署", "SHIP 成功", "已上线 🚀", "任务完成"]
		var bag: Array = _mascot_lang_bag(lines_fr, lines_en, lines_zh)
		lbl.text = bag[randi() % bag.size()]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", _ed_font(8 if milestone else 5))
	lbl.add_theme_color_override("font_color", C_PRIMARY)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 30
	parent.add_child(lbl)
	lbl.reset_size()
	var pw := size.x if size.x > 10 else 320.0
	lbl.position = Vector2(pw * 0.5 - lbl.size.x * 0.5, size.y * 0.12)
	lbl.modulate.a = 0.0
	lbl.scale = Vector2(0.4, 0.4)
	lbl.pivot_offset = lbl.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.2)
	tw.tween_property(lbl, "scale", Vector2(1.15, 1.15), 0.35).set_trans(Tween.TRANS_BACK)
	tw.chain().set_parallel(false)
	tw.tween_property(lbl, "position:y", lbl.position.y - 40.0, 1.4)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 1.0).set_delay(0.6)
	tw.tween_callback(lbl.queue_free)


func _wf_pulse_banner(col: Color) -> void:
	if not is_instance_valid(_status_banner):
		return
	var base := _status_banner.modulate
	var tw := create_tween()
	tw.tween_property(_status_banner, "modulate", Color(col.r * 1.2, col.g * 1.2, col.b * 1.2, 1.0), 0.12)
	tw.tween_property(_status_banner, "modulate", base, 0.35)


func _wf_sparkle_burst(col: Color, n: int = 10) -> void:
	for i in n:
		var d := ColorRect.new()
		d.color = Color(col.r, col.g, col.b, 0.9)
		d.size = Vector2(4, 4)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.z_index = 50
		add_child(d)
		var cx := size.x * 0.5 + randf_range(-40, 40)
		var cy := size.y * 0.25 + randf_range(-20, 20)
		d.position = Vector2(cx, cy)
		var tw := create_tween()
		var dest := Vector2(cx + randf_range(-80, 80), cy + randf_range(-60, 40))
		tw.set_parallel(true)
		tw.tween_property(d, "position", dest, randf_range(0.4, 0.9))
		tw.tween_property(d, "modulate:a", 0.0, 0.7)
		tw.tween_property(d, "size", Vector2(1, 1), 0.7)
		tw.chain().tween_callback(d.queue_free)


func _wf_deploy_ignition() -> void:
	## Début de deploy : le dock « s’allume », le bouton pulse.
	if is_instance_valid(deploy_btn):
		var tw := create_tween()
		tw.tween_property(deploy_btn, "scale", Vector2(1.06, 1.06), 0.12)
		tw.tween_property(deploy_btn, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC)
	_wf_pulse_banner(C_BUSY)
	# Légère secousse d’engagement
	var base := position
	var shake := create_tween()
	for i in 4:
		shake.tween_property(self, "position", base + Vector2(randf_range(-3, 3), randf_range(-2, 2)), 0.04)
	shake.tween_property(self, "position", base, 0.06)
	_wf_sparkle_burst(C_PRIMARY, 14)
	# Titre flottant « LAUNCH »
	var lbl := Label.new()
	lbl.text = "🚀 LAUNCH"
	lbl.add_theme_font_size_override("font_size", _ed_font(4))
	lbl.add_theme_color_override("font_color", C_PRIMARY)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 40
	add_child(lbl)
	lbl.reset_size()
	lbl.position = Vector2(size.x * 0.5 - lbl.size.x * 0.5, size.y * 0.4)
	lbl.modulate.a = 0
	var tw2 := create_tween()
	tw2.tween_property(lbl, "modulate:a", 1.0, 0.15)
	tw2.tween_property(lbl, "position:y", lbl.position.y - 30, 0.8)
	tw2.parallel().tween_property(lbl, "modulate:a", 0.0, 0.5).set_delay(0.35)
	tw2.tween_callback(lbl.queue_free)


func _wf_progress_glow() -> void:
	if not is_instance_valid(progress_bar):
		return
	var tw := create_tween()
	tw.tween_property(progress_bar, "modulate", Color(1.2, 1.15, 1.0, 1.0), 0.15)
	tw.tween_property(progress_bar, "modulate", Color.WHITE, 0.4)


func _wf_upload_energy() -> void:
	_wf_progress_glow()
	_wf_sparkle_burst(C_OK, 6)


func _wf_fail_shake() -> void:
	var base := position
	var shake := create_tween()
	for i in 6:
		shake.tween_property(self, "position", base + Vector2(randf_range(-6, 6), randf_range(-4, 4)), 0.04)
	shake.tween_property(self, "position", base, 0.08)
	_wf_pulse_banner(C_ERR)


func _setup_celebration_ui() -> void:
	_celeb_layer = Control.new()
	_celeb_layer.name = "CelebrationLayer"
	_celeb_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_celeb_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_celeb_layer.z_index = 200
	_celeb_layer.visible = false
	_celeb_layer.modulate = Color(1, 1, 1, 0)
	add_child(_celeb_layer)

	# Fond semi-transparent
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.color = Color(0.06, 0.07, 0.09, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_celeb_layer.add_child(dim)

	# Carte centrale (centrée manuellement au moment du show)
	_celeb_panel = PanelContainer.new()
	_celeb_panel.custom_minimum_size = Vector2(260, 0)
	_celeb_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_celeb_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var psb := StyleBoxFlat.new()
	psb.bg_color = C_CARD
	psb.set_corner_radius_all(16)
	psb.content_margin_left = 20
	psb.content_margin_right = 20
	psb.content_margin_top = 18
	psb.content_margin_bottom = 16
	psb.border_width_left = 2
	psb.border_width_right = 2
	psb.border_width_top = 2
	psb.border_width_bottom = 2
	psb.border_color = C_PRIMARY
	_celeb_panel.add_theme_stylebox_override("panel", psb)
	_celeb_layer.add_child(_celeb_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_celeb_panel.add_child(vbox)

	_celeb_tex = TextureRect.new()
	_celeb_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_celeb_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_celeb_tex.custom_minimum_size = Vector2(120, 140)
	_celeb_tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_celeb_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_celeb_tex)

	_celeb_title = Label.new()
	_celeb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_celeb_title.add_theme_font_size_override("font_size", _ed_font(4))
	_celeb_title.add_theme_color_override("font_color", C_PRIMARY)
	vbox.add_child(_celeb_title)

	_celeb_streak = Label.new()
	_celeb_streak.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_celeb_streak.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_celeb_streak.add_theme_font_size_override("font_size", _ed_font(0))
	_celeb_streak.add_theme_color_override("font_color", Color(0.953, 0.925, 0.878))
	vbox.add_child(_celeb_streak)

	_celeb_total = Label.new()
	_celeb_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_celeb_total.add_theme_font_size_override("font_size", _ed_font(-1))
	_celeb_total.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(_celeb_total)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(btn_row)

	_celeb_share = Button.new()
	_celeb_share.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_celeb_share.pressed.connect(_on_celeb_share)
	btn_row.add_child(_celeb_share)
	_style_secondary_button(_celeb_share)

	_celeb_dismiss = Button.new()
	_celeb_dismiss.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_celeb_dismiss.pressed.connect(_hide_celebration)
	btn_row.add_child(_celeb_dismiss)
	_style_primary_button(_celeb_dismiss)

	# Bouton Chaos célébration (optionnel, visible si préférence active)
	_celeb_chaos_btn = Button.new()
	_celeb_chaos_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_celeb_chaos_btn.pressed.connect(_on_celeb_chaos)
	vbox.add_child(_celeb_chaos_btn)
	_style_secondary_button(_celeb_chaos_btn)


func _celebrate_ship() -> void:
	if not is_instance_valid(_celeb_layer) or not is_instance_valid(_celeb_panel):
		return
	_celeb_active = true

	if is_instance_valid(_celeb_tex):
		if _mascot_lion_tex:
			_celeb_tex.texture = _mascot_lion_tex
		elif _mascot_head_tex:
			_celeb_tex.texture = _mascot_head_tex

	_celeb_title.text = tr_ui("ship_title")
	if _ship_week_count <= 1 and _ship_total <= 1:
		_celeb_streak.text = tr_ui("ship_first")
	else:
		_celeb_streak.text = tr_ui("ship_streak") % _ship_week_count
	_celeb_total.text = tr_ui("ship_total") % _ship_total
	if is_instance_valid(_celeb_share):
		_celeb_share.text = tr_ui("ship_share")
	if is_instance_valid(_celeb_dismiss):
		_celeb_dismiss.text = tr_ui("ship_dismiss")
	if is_instance_valid(_celeb_chaos_btn):
		_celeb_chaos_btn.text = tr_ui("ship_replay_fx")
		_celeb_chaos_btn.visible = true
		_celeb_chaos_btn.tooltip_text = tr_ui("ship_replay_fx_tip")

	# Centrer la carte
	var pw := size.x if size.x > 10.0 else 320.0
	var ph := size.y if size.y > 10.0 else 600.0
	_celeb_panel.reset_size()
	await get_tree().process_frame
	if not is_instance_valid(_celeb_panel):
		return
	var psz := _celeb_panel.get_combined_minimum_size()
	_celeb_panel.position = Vector2((pw - psz.x) * 0.5, (ph - psz.y) * 0.38)
	_celeb_panel.scale = Vector2(0.7, 0.7)
	_celeb_panel.pivot_offset = psz * 0.5

	_celeb_layer.visible = true
	_celeb_layer.modulate = Color(1, 1, 1, 0)

	# Flash doré plein écran
	_spawn_gold_flash()

	# Entrée carte
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_celeb_layer, "modulate:a", 1.0, 0.28)
	t.tween_property(_celeb_panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Confettis enrichis
	_spawn_confetti()
	# Seconde salve
	get_tree().create_timer(0.35).timeout.connect(func():
		if _celeb_active:
			_spawn_confetti()
	)

	# Mascotte qui danse (plus longtemps)
	_celeb_dance_mascot()

	# Son optionnel très court
	_play_ship_sfx()


func _spawn_gold_flash() -> void:
	if not is_instance_valid(_celeb_layer):
		return
	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	flash.color = Color(1.0, 0.85, 0.35, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 5
	_celeb_layer.add_child(flash)
	_celeb_layer.move_child(flash, 1)  # au-dessus du dim
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.55, 0.08)
	tw.tween_property(flash, "color:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(flash.queue_free)


func _celeb_dance_mascot() -> void:
	if not is_instance_valid(_celeb_tex):
		return
	_celeb_tex.pivot_offset = _celeb_tex.custom_minimum_size * 0.5
	var hop := create_tween()
	hop.set_loops(4)
	hop.tween_property(_celeb_tex, "rotation_degrees", -14.0, 0.10)
	hop.tween_property(_celeb_tex, "rotation_degrees", 14.0, 0.12)
	hop.tween_property(_celeb_tex, "rotation_degrees", -10.0, 0.10)
	hop.tween_property(_celeb_tex, "rotation_degrees", 10.0, 0.10)
	hop.tween_property(_celeb_tex, "rotation_degrees", 0.0, 0.10)
	var bounce := create_tween()
	bounce.set_loops(4)
	bounce.tween_property(_celeb_tex, "scale", Vector2(1.15, 0.9), 0.12)
	bounce.tween_property(_celeb_tex, "scale", Vector2(0.95, 1.12), 0.12)
	bounce.tween_property(_celeb_tex, "scale", Vector2.ONE, 0.12)


func _play_ship_sfx() -> void:
	## Bip doré très court généré en mémoire (pas de fichier externe). Désactivable.
	if not _celeb_sfx_enabled:
		return
	if not is_instance_valid(_celeb_sfx):
		_celeb_sfx = AudioStreamPlayer.new()
		_celeb_sfx.name = "ShipSfx"
		_celeb_sfx.bus = "Master"
		_celeb_sfx.volume_db = -8.0
		add_child(_celeb_sfx)
	var stream := _make_ship_beep_stream()
	if stream == null:
		return
	_celeb_sfx.stream = stream
	_celeb_sfx.play()


func _make_ship_beep_stream() -> AudioStreamWAV:
	## Deux notes montantes (~0.18 s) — sensation « ding » de succès.
	var sample_rate := 22050
	var duration := 0.18
	var n := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / float(sample_rate)
		var freq := 523.25 if t < 0.08 else 659.25  # C5 → E5
		var env := 1.0
		if t < 0.01:
			env = t / 0.01
		elif t > duration - 0.04:
			env = maxf(0.0, (duration - t) / 0.04)
		var s := sin(t * freq * TAU) * env * 0.35
		var v := int(clampf(s * 32767.0, -32768, 32767))
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.data = data
	return wav


func _spawn_confetti() -> void:
	if not is_instance_valid(_celeb_layer):
		return
	# Mode CRT : flash + glitch à la place de confettis soft
	if _crt_motion or _ui_theme in ["ps2", "underground"]:
		_crt_flash_glitch()
		return
	var colors := [
		C_PRIMARY,
		C_ACCENT,
		Color(1.0, 0.85, 0.25),
		Color(1.0, 0.92, 0.45),
		Color(0.95, 0.75, 0.15),
		Color(0.98, 0.95, 0.88),
		C_OK,
		Color(1.0, 0.95, 0.6),
	]
	var panel_w := size.x if size.x > 10.0 else 320.0
	var panel_h := size.y if size.y > 10.0 else 600.0
	for i in range(16):
		var c := ColorRect.new()
		var s := randf_range(4.0, 11.0)
		c.size = Vector2(s, s * randf_range(0.6, 1.4))
		c.color = colors[randi() % colors.size()]
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.position = Vector2(randf_range(0, panel_w), randf_range(-30, panel_h * 0.35))
		c.rotation_degrees = randf_range(0, 360)
		_celeb_layer.add_child(c)
		var dest := c.position + Vector2(randf_range(-40, 40), randf_range(panel_h * 0.4, panel_h * 0.75))
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(c, "position", dest, randf_range(1.2, 2.2)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(c, "modulate:a", 0.0, randf_range(1.0, 2.0)).set_delay(0.4)
		tw.tween_property(c, "rotation_degrees", c.rotation_degrees + randf_range(-180, 180), 1.8)
		tw.chain().tween_callback(c.queue_free)


func _hide_celebration() -> void:
	if not _celeb_active or not is_instance_valid(_celeb_layer):
		return
	var t := create_tween()
	t.tween_property(_celeb_layer, "modulate:a", 0.0, 0.2)
	t.tween_callback(func() -> void:
		if is_instance_valid(_celeb_layer):
			_celeb_layer.visible = false
		_celeb_active = false
	)


func _on_celeb_share() -> void:
	# Copie rapide du lien store public pour le jeu sélectionné (sans token de campagne).
	if selected_game_id < 1:
		_feedback(tr_ui("share_need_game"), "warn")
		return
	var url := ""
	# Préférer un lien tracké déjà généré si disponible
	if not _current_share.is_empty():
		var path := str(_current_share.get("path", "")).strip_edges()
		if path != "":
			url = _full_share_url(path)
	if url == "":
		url = _store_base() + "game.html?id=%d" % selected_game_id
	DisplayServer.clipboard_set(url)
	_feedback(tr_ui("share_copied"), "ok")
	_log("Lien store copié: %s" % url)


func _on_celeb_chaos() -> void:
	## Replay FX immersif (thématique) — l’impact du ship, rejouable.
	if _chaos_active:
		return
	_spawn_confetti()
	_wf_impact_title(_ship_total in [1, 5, 10, 25, 50, 100])
	_chaos_start_soft(_wf_pick_success_fx())


func _chaos_start_soft(kind: String = "explode") -> void:
	## Chaos « célébration » : intensité douce, durée courte, auto-restore forcé.
	if _chaos_active:
		return
	var prev_int := _chaos_intensity
	var prev_dur := _chaos_duration_mult
	var prev_auto := _chaos_auto_restore
	_chaos_intensity = minf(_chaos_intensity, 0.85)  # jamais plus fort que Zen/Normal soft
	_chaos_duration_mult = 0.7
	_chaos_auto_restore = true
	_chaos_start(kind)
	# Restaure les prefs utilisateur (l’effet tourne déjà avec les valeurs soft)
	_chaos_intensity = prev_int
	_chaos_duration_mult = prev_dur
	_chaos_auto_restore = prev_auto


# ══════════════════════════════════════════════════════════════════════════════
# THÈMES (default / matrix / sunrise / forest / sepia)
# ══════════════════════════════════════════════════════════════════════════════

func _theme_presets() -> Dictionary:
	## Thèmes inspirés de l’esthétique Circe / Asereth : rouge profond, perles, sakura, contraste élégant.
	return {
		# Circe — thème principal (image de référence) : cramoisi profond, perles rouges, fleurs blanches
		"circe": {
			"primary": Color(0.86, 0.14, 0.22),
			"primary_fg": Color(0.98, 0.95, 0.94),
			"accent": Color(0.95, 0.82, 0.78),
			"surface": Color(0.14, 0.05, 0.07),
			"card": Color(0.10, 0.03, 0.05),
			"border": Color(0.42, 0.12, 0.18),
			"muted": Color(0.68, 0.48, 0.52),
			"ok": Color(0.35, 0.78, 0.52),
			"err": Color(0.95, 0.40, 0.42),
			"text": Color(0.98, 0.94, 0.92),
			"hover": Color(0.20, 0.07, 0.10),
			"pressed": Color(0.08, 0.02, 0.04),
			"banner_idle": Color(0.09, 0.03, 0.04, 0.94),
			"banner_info": Color(0.14, 0.05, 0.07, 0.95),
		},
		# Sakura — douceur des fleurs de cerisier, rose poudré & blanc
		"sakura": {
			"primary": Color(0.92, 0.48, 0.58),
			"primary_fg": Color(0.18, 0.06, 0.10),
			"accent": Color(0.98, 0.88, 0.90),
			"surface": Color(0.22, 0.12, 0.15),
			"card": Color(0.16, 0.09, 0.11),
			"border": Color(0.48, 0.28, 0.34),
			"muted": Color(0.78, 0.58, 0.62),
			"ok": Color(0.45, 0.78, 0.58),
			"err": Color(0.90, 0.42, 0.48),
			"text": Color(0.99, 0.95, 0.96),
			"hover": Color(0.28, 0.16, 0.19),
			"pressed": Color(0.12, 0.06, 0.08),
			"banner_idle": Color(0.14, 0.07, 0.09, 0.94),
			"banner_info": Color(0.20, 0.11, 0.14, 0.95),
		},
		# Onyx — nuit noire, perles rouges, élégance sombre
		"onyx": {
			"primary": Color(0.82, 0.12, 0.20),
			"primary_fg": Color(0.98, 0.95, 0.94),
			"accent": Color(0.90, 0.75, 0.70),
			"surface": Color(0.06, 0.05, 0.06),
			"card": Color(0.04, 0.03, 0.04),
			"border": Color(0.28, 0.10, 0.14),
			"muted": Color(0.55, 0.42, 0.45),
			"ok": Color(0.30, 0.72, 0.48),
			"err": Color(0.90, 0.35, 0.38),
			"text": Color(0.94, 0.90, 0.90),
			"hover": Color(0.12, 0.08, 0.09),
			"pressed": Color(0.03, 0.02, 0.03),
			"banner_idle": Color(0.04, 0.03, 0.03, 0.95),
			"banner_info": Color(0.08, 0.05, 0.06, 0.95),
		},
		# Ivory — kimono blanc, accents rouges, lumière douce
		"ivory": {
			"primary": Color(0.78, 0.18, 0.26),
			"primary_fg": Color(0.98, 0.96, 0.95),
			"accent": Color(0.55, 0.22, 0.28),
			"surface": Color(0.28, 0.24, 0.23),
			"card": Color(0.22, 0.19, 0.18),
			"border": Color(0.48, 0.32, 0.34),
			"muted": Color(0.68, 0.58, 0.56),
			"ok": Color(0.32, 0.68, 0.48),
			"err": Color(0.88, 0.42, 0.42),
			"text": Color(0.97, 0.94, 0.92),
			"hover": Color(0.34, 0.28, 0.27),
			"pressed": Color(0.18, 0.14, 0.13),
			"banner_idle": Color(0.18, 0.15, 0.14, 0.94),
			"banner_info": Color(0.24, 0.20, 0.19, 0.95),
		},
		# Ember — braises chaudes, or & rouge flamboyant
		"ember": {
			"primary": Color(0.95, 0.38, 0.18),
			"primary_fg": Color(0.12, 0.05, 0.02),
			"accent": Color(0.98, 0.72, 0.35),
			"surface": Color(0.18, 0.08, 0.05),
			"card": Color(0.13, 0.05, 0.03),
			"border": Color(0.48, 0.22, 0.12),
			"muted": Color(0.72, 0.52, 0.40),
			"ok": Color(0.42, 0.78, 0.45),
			"err": Color(0.92, 0.38, 0.32),
			"text": Color(0.99, 0.94, 0.88),
			"hover": Color(0.24, 0.12, 0.07),
			"pressed": Color(0.10, 0.04, 0.02),
			"banner_idle": Color(0.12, 0.05, 0.03, 0.94),
			"banner_info": Color(0.18, 0.08, 0.05, 0.95),
		},
		# Matrix (classique conservé)
		"matrix": {
			"primary": Color(0.20, 0.95, 0.35),
			"primary_fg": Color(0.02, 0.08, 0.03),
			"accent": Color(0.10, 0.70, 0.25),
			"surface": Color(0.04, 0.10, 0.05),
			"card": Color(0.02, 0.06, 0.03),
			"border": Color(0.12, 0.35, 0.18),
			"muted": Color(0.35, 0.55, 0.40),
			"ok": Color(0.25, 0.95, 0.45),
			"err": Color(0.85, 0.25, 0.25),
			"text": Color(0.55, 1.0, 0.65),
			"hover": Color(0.06, 0.16, 0.08),
			"pressed": Color(0.03, 0.09, 0.04),
			"banner_idle": Color(0.02, 0.06, 0.03, 0.94),
			"banner_info": Color(0.04, 0.10, 0.05, 0.95),
		},
		# Forest (classique conservé)
		"forest": {
			"primary": Color(0.55, 0.82, 0.42),
			"primary_fg": Color(0.08, 0.14, 0.06),
			"accent": Color(0.35, 0.65, 0.40),
			"surface": Color(0.12, 0.18, 0.14),
			"card": Color(0.09, 0.14, 0.11),
			"border": Color(0.22, 0.32, 0.24),
			"muted": Color(0.55, 0.65, 0.55),
			"ok": Color(0.40, 0.85, 0.50),
			"err": Color(0.90, 0.50, 0.45),
			"text": Color(0.90, 0.95, 0.88),
			"hover": Color(0.16, 0.24, 0.18),
			"pressed": Color(0.08, 0.12, 0.09),
			"banner_idle": Color(0.08, 0.12, 0.09, 0.94),
			"banner_info": Color(0.12, 0.18, 0.14, 0.95),
		},
		# PS2 — phosphor green, hard edges, CRT era
		"ps2": {
			"primary": Color(0.20, 0.95, 0.35),
			"primary_fg": Color(0.02, 0.06, 0.03),
			"accent": Color(0.55, 1.0, 0.65),
			"surface": Color(0.05, 0.07, 0.06),
			"card": Color(0.03, 0.04, 0.04),
			"border": Color(0.15, 0.40, 0.20),
			"muted": Color(0.40, 0.55, 0.42),
			"ok": Color(0.25, 0.95, 0.40),
			"err": Color(0.95, 0.25, 0.20),
			"text": Color(0.75, 0.95, 0.78),
			"hover": Color(0.08, 0.12, 0.09),
			"pressed": Color(0.02, 0.04, 0.03),
			"banner_idle": Color(0.02, 0.04, 0.03, 0.95),
			"banner_info": Color(0.04, 0.08, 0.05, 0.95),
			"radius_card": 3,
			"radius_btn": 2,
			"radius_field": 2,
			"border_w": 2,
			"shadow_size": 0,
			"shadow_alpha": 0.0,
			"font_delta": 0,
		},
		# Underground — blood CRT, NFS/horror menu energy
		"underground": {
			"primary": Color(0.92, 0.12, 0.10),
			"primary_fg": Color(0.98, 0.95, 0.92),
			"accent": Color(1.0, 0.45, 0.15),
			"surface": Color(0.06, 0.04, 0.05),
			"card": Color(0.04, 0.02, 0.03),
			"border": Color(0.35, 0.08, 0.08),
			"muted": Color(0.55, 0.35, 0.35),
			"ok": Color(0.35, 0.75, 0.40),
			"err": Color(1.0, 0.25, 0.18),
			"text": Color(0.92, 0.88, 0.85),
			"hover": Color(0.12, 0.05, 0.05),
			"pressed": Color(0.03, 0.01, 0.01),
			"banner_idle": Color(0.04, 0.02, 0.02, 0.95),
			"banner_info": Color(0.08, 0.03, 0.03, 0.95),
			"radius_card": 2,
			"radius_btn": 2,
			"radius_field": 2,
			"border_w": 2,
			"shadow_size": 0,
			"shadow_alpha": 0.0,
			"font_delta": 0,
		},

		# Chicago 1930 — speakeasy, brass, newspaper ink
		"chicago30": {
			"primary": Color(0.72, 0.55, 0.22),
			"primary_fg": Color(0.08, 0.06, 0.04),
			"accent": Color(0.85, 0.72, 0.45),
			"surface": Color(0.12, 0.10, 0.08),
			"card": Color(0.08, 0.07, 0.05),
			"border": Color(0.42, 0.32, 0.16),
			"muted": Color(0.58, 0.50, 0.38),
			"ok": Color(0.45, 0.62, 0.38),
			"err": Color(0.75, 0.22, 0.18),
			"text": Color(0.92, 0.88, 0.78),
			"hover": Color(0.18, 0.14, 0.10),
			"pressed": Color(0.05, 0.04, 0.03),
			"banner_idle": Color(0.08, 0.06, 0.04, 0.95),
			"banner_info": Color(0.14, 0.11, 0.07, 0.95),
			"radius_card": 4,
			"radius_btn": 3,
			"radius_field": 3,
			"border_w": 1,
			"shadow_size": 4,
			"shadow_alpha": 0.35,
			"font_delta": 0,
		},
		# Gangster 90s — black / gold / chrome hip-hop
		"gangster90": {
			"primary": Color(0.95, 0.78, 0.18),
			"primary_fg": Color(0.05, 0.04, 0.02),
			"accent": Color(0.92, 0.92, 0.95),
			"surface": Color(0.06, 0.06, 0.07),
			"card": Color(0.03, 0.03, 0.04),
			"border": Color(0.55, 0.45, 0.12),
			"muted": Color(0.55, 0.52, 0.42),
			"ok": Color(0.35, 0.80, 0.45),
			"err": Color(0.90, 0.25, 0.22),
			"text": Color(0.96, 0.94, 0.88),
			"hover": Color(0.12, 0.11, 0.08),
			"pressed": Color(0.02, 0.02, 0.02),
			"banner_idle": Color(0.04, 0.04, 0.04, 0.96),
			"banner_info": Color(0.10, 0.09, 0.05, 0.95),
			"radius_card": 6,
			"radius_btn": 4,
			"radius_field": 4,
			"border_w": 1,
			"shadow_size": 8,
			"shadow_alpha": 0.4,
			"font_delta": 0,
		},
		# Gangsta / R&B 2000s — purple, pink chrome, bling
		"gangsta00": {
			"primary": Color(0.72, 0.28, 0.85),
			"primary_fg": Color(0.98, 0.95, 1.0),
			"accent": Color(1.0, 0.45, 0.72),
			"surface": Color(0.08, 0.05, 0.12),
			"card": Color(0.05, 0.03, 0.08),
			"border": Color(0.45, 0.18, 0.55),
			"muted": Color(0.62, 0.48, 0.70),
			"ok": Color(0.40, 0.85, 0.70),
			"err": Color(1.0, 0.35, 0.45),
			"text": Color(0.96, 0.92, 0.98),
			"hover": Color(0.14, 0.08, 0.20),
			"pressed": Color(0.04, 0.02, 0.06),
			"banner_idle": Color(0.05, 0.03, 0.08, 0.95),
			"banner_info": Color(0.12, 0.06, 0.16, 0.95),
			"radius_card": 10,
			"radius_btn": 8,
			"radius_field": 8,
			"border_w": 1,
			"shadow_size": 10,
			"shadow_alpha": 0.35,
			"font_delta": 0,
		},

		# Afrofuturisme / Teranga — or, terre, baobab, nuit dakaroise, néon warm
		"teranga": {
			"primary": Color(0.92, 0.62, 0.18),
			"primary_fg": Color(0.12, 0.08, 0.04),
			"accent": Color(0.95, 0.78, 0.42),
			"surface": Color(0.10, 0.07, 0.05),
			"card": Color(0.07, 0.05, 0.03),
			"border": Color(0.55, 0.38, 0.14),
			"muted": Color(0.68, 0.55, 0.38),
			"ok": Color(0.42, 0.78, 0.48),
			"err": Color(0.90, 0.32, 0.22),
			"text": Color(0.98, 0.94, 0.86),
			"hover": Color(0.16, 0.11, 0.07),
			"pressed": Color(0.05, 0.03, 0.02),
			"banner_idle": Color(0.08, 0.05, 0.03, 0.95),
			"banner_info": Color(0.14, 0.10, 0.05, 0.95),
			"radius_card": 12,
			"radius_btn": 10,
			"radius_field": 10,
			"border_w": 1,
			"shadow_size": 8,
			"shadow_alpha": 0.38,
			"font_delta": 0,
		},
		# Wax / Ankara — motifs tissus africains, jaune vif, indigo, rouge, vert
		"wax": {
			"primary": Color(0.95, 0.55, 0.08),
			"primary_fg": Color(0.12, 0.06, 0.02),
			"accent": Color(0.15, 0.35, 0.75),
			"surface": Color(0.12, 0.08, 0.06),
			"card": Color(0.08, 0.05, 0.04),
			"border": Color(0.85, 0.25, 0.15),
			"muted": Color(0.75, 0.55, 0.35),
			"ok": Color(0.25, 0.72, 0.38),
			"err": Color(0.90, 0.22, 0.18),
			"text": Color(0.98, 0.94, 0.88),
			"hover": Color(0.18, 0.12, 0.08),
			"pressed": Color(0.06, 0.04, 0.03),
			"banner_idle": Color(0.10, 0.06, 0.04, 0.95),
			"banner_info": Color(0.16, 0.10, 0.06, 0.95),
			"radius_card": 10,
			"radius_btn": 8,
			"radius_field": 8,
			"border_w": 2,
			"shadow_size": 6,
			"shadow_alpha": 0.35,
			"font_delta": 0,
		},
		# Sahel — dunes, terre cuite, ocre, ciel brûlé
		"sahel": {
			"primary": Color(0.88, 0.48, 0.22),
			"primary_fg": Color(0.12, 0.06, 0.03),
			"accent": Color(0.95, 0.82, 0.45),
			"surface": Color(0.14, 0.10, 0.07),
			"card": Color(0.10, 0.07, 0.05),
			"border": Color(0.55, 0.35, 0.18),
			"muted": Color(0.70, 0.55, 0.38),
			"ok": Color(0.55, 0.70, 0.35),
			"err": Color(0.85, 0.30, 0.20),
			"text": Color(0.96, 0.90, 0.80),
			"hover": Color(0.20, 0.14, 0.09),
			"pressed": Color(0.07, 0.05, 0.03),
			"banner_idle": Color(0.12, 0.08, 0.05, 0.95),
			"banner_info": Color(0.18, 0.12, 0.07, 0.95),
			"radius_card": 8,
			"radius_btn": 6,
			"radius_field": 6,
			"border_w": 1,
			"shadow_size": 8,
			"shadow_alpha": 0.40,
			"font_delta": 0,
		},
		# Savane — herbes hautes, soleil, baobab, vert-or
		"savane": {
			"primary": Color(0.45, 0.72, 0.28),
			"primary_fg": Color(0.08, 0.12, 0.04),
			"accent": Color(0.95, 0.78, 0.22),
			"surface": Color(0.10, 0.12, 0.07),
			"card": Color(0.07, 0.09, 0.05),
			"border": Color(0.40, 0.50, 0.22),
			"muted": Color(0.58, 0.65, 0.42),
			"ok": Color(0.50, 0.82, 0.35),
			"err": Color(0.88, 0.35, 0.22),
			"text": Color(0.94, 0.96, 0.88),
			"hover": Color(0.14, 0.17, 0.10),
			"pressed": Color(0.05, 0.06, 0.03),
			"banner_idle": Color(0.08, 0.10, 0.05, 0.95),
			"banner_info": Color(0.12, 0.15, 0.08, 0.95),
			"radius_card": 12,
			"radius_btn": 10,
			"radius_field": 10,
			"border_w": 1,
			"shadow_size": 8,
			"shadow_alpha": 0.36,
			"font_delta": 0,
		},
		# Synthwave / Outrun 80s — rose/cyan, grille, soleil couchant, chrome
		"synthwave": {
			"primary": Color(1.0, 0.22, 0.72),
			"primary_fg": Color(0.08, 0.02, 0.08),
			"accent": Color(0.25, 0.92, 1.0),
			"surface": Color(0.08, 0.04, 0.14),
			"card": Color(0.05, 0.02, 0.10),
			"border": Color(0.55, 0.18, 0.55),
			"muted": Color(0.70, 0.45, 0.75),
			"ok": Color(0.30, 0.95, 0.75),
			"err": Color(1.0, 0.35, 0.40),
			"text": Color(0.98, 0.92, 1.0),
			"hover": Color(0.14, 0.06, 0.22),
			"pressed": Color(0.04, 0.01, 0.08),
			"banner_idle": Color(0.06, 0.03, 0.12, 0.95),
			"banner_info": Color(0.12, 0.05, 0.18, 0.95),
			"radius_card": 8,
			"radius_btn": 6,
			"radius_field": 6,
			"border_w": 1,
			"shadow_size": 12,
			"shadow_alpha": 0.45,
			"font_delta": 0,
		},
		# Cyberpunk / Neo-Tokyo — noir, rose fluo, cyan, pluie, glitch
		"cyberpunk": {
			"primary": Color(0.0, 0.95, 0.95),
			"primary_fg": Color(0.02, 0.06, 0.08),
			"accent": Color(1.0, 0.15, 0.55),
			"surface": Color(0.04, 0.05, 0.07),
			"card": Color(0.02, 0.03, 0.05),
			"border": Color(0.15, 0.45, 0.50),
			"muted": Color(0.40, 0.55, 0.60),
			"ok": Color(0.25, 0.95, 0.55),
			"err": Color(1.0, 0.25, 0.40),
			"text": Color(0.90, 0.98, 1.0),
			"hover": Color(0.08, 0.12, 0.15),
			"pressed": Color(0.01, 0.02, 0.03),
			"banner_idle": Color(0.03, 0.04, 0.06, 0.96),
			"banner_info": Color(0.06, 0.10, 0.12, 0.95),
			"radius_card": 4,
			"radius_btn": 3,
			"radius_field": 3,
			"border_w": 1,
			"shadow_size": 10,
			"shadow_alpha": 0.5,
			"font_delta": 0,
		},
		# Steampunk / laiton — cuivre, bronze, engrenages, sépia industriel
		"steampunk": {
			"primary": Color(0.72, 0.45, 0.18),
			"primary_fg": Color(0.12, 0.08, 0.04),
			"accent": Color(0.85, 0.65, 0.35),
			"surface": Color(0.12, 0.09, 0.06),
			"card": Color(0.08, 0.06, 0.04),
			"border": Color(0.48, 0.32, 0.14),
			"muted": Color(0.60, 0.48, 0.32),
			"ok": Color(0.45, 0.65, 0.35),
			"err": Color(0.78, 0.28, 0.18),
			"text": Color(0.94, 0.88, 0.75),
			"hover": Color(0.18, 0.13, 0.08),
			"pressed": Color(0.05, 0.04, 0.02),
			"banner_idle": Color(0.08, 0.06, 0.04, 0.95),
			"banner_info": Color(0.14, 0.10, 0.06, 0.95),
			"radius_card": 6,
			"radius_btn": 4,
			"radius_field": 4,
			"border_w": 2,
			"shadow_size": 6,
			"shadow_alpha": 0.4,
			"font_delta": 0,
		},
		# Horror / gothic CRT — vert malade, rouge sang, scanlines sales
		"horror": {
			"primary": Color(0.55, 0.85, 0.25),
			"primary_fg": Color(0.04, 0.08, 0.02),
			"accent": Color(0.85, 0.15, 0.12),
			"surface": Color(0.04, 0.06, 0.03),
			"card": Color(0.02, 0.04, 0.02),
			"border": Color(0.25, 0.40, 0.12),
			"muted": Color(0.40, 0.55, 0.30),
			"ok": Color(0.35, 0.70, 0.30),
			"err": Color(0.90, 0.18, 0.15),
			"text": Color(0.75, 0.95, 0.55),
			"hover": Color(0.08, 0.12, 0.05),
			"pressed": Color(0.01, 0.02, 0.01),
			"banner_idle": Color(0.03, 0.05, 0.02, 0.96),
			"banner_info": Color(0.06, 0.10, 0.04, 0.95),
			"radius_card": 2,
			"radius_btn": 2,
			"radius_field": 2,
			"border_w": 2,
			"shadow_size": 0,
			"shadow_alpha": 0.0,
			"font_delta": 0,
		},
		# Minimal / clean — blanc cassé, gris, une seule accent
		"minimal": {
			"primary": Color(0.22, 0.45, 0.85),
			"primary_fg": Color(0.98, 0.98, 1.0),
			"accent": Color(0.35, 0.55, 0.90),
			"surface": Color(0.94, 0.94, 0.95),
			"card": Color(1.0, 1.0, 1.0),
			"border": Color(0.78, 0.80, 0.84),
			"muted": Color(0.45, 0.48, 0.52),
			"ok": Color(0.25, 0.70, 0.45),
			"err": Color(0.85, 0.28, 0.28),
			"text": Color(0.12, 0.13, 0.16),
			"hover": Color(0.90, 0.91, 0.93),
			"pressed": Color(0.85, 0.86, 0.88),
			"banner_idle": Color(0.92, 0.93, 0.94, 0.96),
			"banner_info": Color(0.88, 0.90, 0.94, 0.95),
			"radius_card": 10,
			"radius_btn": 8,
			"radius_field": 8,
			"border_w": 1,
			"shadow_size": 4,
			"shadow_alpha": 0.12,
			"font_delta": 0,
		},
		# Pixel / 8-bit — palette limitée, coins durs, Game Boy / NES
		"pixel": {
			"primary": Color(0.35, 0.65, 0.25),
			"primary_fg": Color(0.90, 0.95, 0.85),
			"accent": Color(0.95, 0.75, 0.20),
			"surface": Color(0.10, 0.12, 0.08),
			"card": Color(0.06, 0.08, 0.05),
			"border": Color(0.30, 0.40, 0.20),
			"muted": Color(0.50, 0.58, 0.40),
			"ok": Color(0.40, 0.75, 0.30),
			"err": Color(0.85, 0.30, 0.20),
			"text": Color(0.85, 0.92, 0.75),
			"hover": Color(0.14, 0.16, 0.10),
			"pressed": Color(0.04, 0.05, 0.03),
			"banner_idle": Color(0.06, 0.08, 0.05, 0.95),
			"banner_info": Color(0.10, 0.12, 0.08, 0.95),
			"radius_card": 0,
			"radius_btn": 0,
			"radius_field": 0,
			"border_w": 2,
			"shadow_size": 0,
			"shadow_alpha": 0.0,
			"font_delta": 0,
		},
		# Vaporwave — rose pastel, turquoise, statues grecques, soleil
		"vaporwave": {
			"primary": Color(0.95, 0.45, 0.75),
			"primary_fg": Color(0.15, 0.05, 0.12),
			"accent": Color(0.35, 0.90, 0.88),
			"surface": Color(0.18, 0.12, 0.22),
			"card": Color(0.12, 0.08, 0.16),
			"border": Color(0.55, 0.35, 0.55),
			"muted": Color(0.75, 0.55, 0.72),
			"ok": Color(0.40, 0.85, 0.70),
			"err": Color(0.95, 0.40, 0.50),
			"text": Color(0.98, 0.92, 0.96),
			"hover": Color(0.24, 0.16, 0.28),
			"pressed": Color(0.08, 0.05, 0.12),
			"banner_idle": Color(0.12, 0.08, 0.16, 0.94),
			"banner_info": Color(0.18, 0.12, 0.22, 0.95),
			"radius_card": 14,
			"radius_btn": 12,
			"radius_field": 12,
			"border_w": 1,
			"shadow_size": 10,
			"shadow_alpha": 0.3,
			"font_delta": 0,
		},

		# Manga / shōnen — noir, rouge sang, énergie, contrastes forts
		"manga": {
			"primary": Color(0.90, 0.12, 0.18),
			"primary_fg": Color(0.98, 0.95, 0.95),
			"accent": Color(0.95, 0.95, 0.95),
			"surface": Color(0.08, 0.07, 0.08),
			"card": Color(0.04, 0.03, 0.04),
			"border": Color(0.35, 0.12, 0.14),
			"muted": Color(0.55, 0.45, 0.46),
			"ok": Color(0.30, 0.75, 0.45),
			"err": Color(0.95, 0.20, 0.22),
			"text": Color(0.96, 0.94, 0.93),
			"hover": Color(0.14, 0.10, 0.11),
			"pressed": Color(0.02, 0.02, 0.02),
			"banner_idle": Color(0.05, 0.04, 0.04, 0.96),
			"banner_info": Color(0.12, 0.06, 0.07, 0.95),
			"radius_card": 4,
			"radius_btn": 3,
			"radius_field": 3,
			"border_w": 2,
			"shadow_size": 6,
			"shadow_alpha": 0.35,
			"font_delta": 0,
		},
		# Océan / aquatique — bleu profond, turquoise, écume
		"ocean": {
			"primary": Color(0.12, 0.55, 0.72),
			"primary_fg": Color(0.95, 0.98, 1.0),
			"accent": Color(0.35, 0.85, 0.80),
			"surface": Color(0.05, 0.10, 0.14),
			"card": Color(0.03, 0.07, 0.10),
			"border": Color(0.15, 0.40, 0.50),
			"muted": Color(0.40, 0.60, 0.65),
			"ok": Color(0.30, 0.80, 0.60),
			"err": Color(0.90, 0.35, 0.40),
			"text": Color(0.90, 0.96, 0.98),
			"hover": Color(0.08, 0.15, 0.20),
			"pressed": Color(0.02, 0.04, 0.06),
			"banner_idle": Color(0.04, 0.08, 0.11, 0.95),
			"banner_info": Color(0.08, 0.14, 0.18, 0.95),
			"radius_card": 12,
			"radius_btn": 10,
			"radius_field": 10,
			"border_w": 1,
			"shadow_size": 8,
			"shadow_alpha": 0.3,
			"font_delta": 0,
		},
		# Brutaliste — béton, gris, noir, angles durs
		"brutalist": {
			"primary": Color(0.85, 0.35, 0.15),
			"primary_fg": Color(0.98, 0.96, 0.94),
			"accent": Color(0.70, 0.70, 0.68),
			"surface": Color(0.18, 0.18, 0.17),
			"card": Color(0.12, 0.12, 0.11),
			"border": Color(0.40, 0.40, 0.38),
			"muted": Color(0.55, 0.55, 0.52),
			"ok": Color(0.40, 0.65, 0.40),
			"err": Color(0.80, 0.25, 0.20),
			"text": Color(0.92, 0.92, 0.90),
			"hover": Color(0.24, 0.24, 0.22),
			"pressed": Color(0.08, 0.08, 0.07),
			"banner_idle": Color(0.14, 0.14, 0.13, 0.96),
			"banner_info": Color(0.20, 0.20, 0.18, 0.95),
			"radius_card": 0,
			"radius_btn": 0,
			"radius_field": 0,
			"border_w": 2,
			"shadow_size": 0,
			"shadow_alpha": 0.0,
			"font_delta": 0,
		},
		# Western / désert — ocre, poussière, cuir, soleil brûlant
		"western": {
			"primary": Color(0.82, 0.45, 0.18),
			"primary_fg": Color(0.12, 0.06, 0.02),
			"accent": Color(0.90, 0.70, 0.35),
			"surface": Color(0.16, 0.11, 0.07),
			"card": Color(0.11, 0.07, 0.04),
			"border": Color(0.50, 0.32, 0.15),
			"muted": Color(0.65, 0.50, 0.35),
			"ok": Color(0.45, 0.65, 0.30),
			"err": Color(0.80, 0.25, 0.15),
			"text": Color(0.96, 0.90, 0.78),
			"hover": Color(0.22, 0.15, 0.09),
			"pressed": Color(0.06, 0.04, 0.02),
			"banner_idle": Color(0.10, 0.07, 0.04, 0.95),
			"banner_info": Color(0.16, 0.11, 0.06, 0.95),
			"radius_card": 6,
			"radius_btn": 4,
			"radius_field": 4,
			"border_w": 1,
			"shadow_size": 6,
			"shadow_alpha": 0.35,
			"font_delta": 0,
		},
		# Comic book US / super-héros — rouge, bleu, jaune primaires, pop
		"comicbook": {
			"primary": Color(0.90, 0.15, 0.18),
			"primary_fg": Color(1.0, 1.0, 1.0),
			"accent": Color(0.95, 0.80, 0.10),
			"surface": Color(0.08, 0.12, 0.28),
			"card": Color(0.05, 0.08, 0.20),
			"border": Color(0.25, 0.35, 0.65),
			"muted": Color(0.50, 0.55, 0.70),
			"ok": Color(0.25, 0.75, 0.35),
			"err": Color(0.95, 0.20, 0.15),
			"text": Color(0.98, 0.97, 0.95),
			"hover": Color(0.12, 0.18, 0.35),
			"pressed": Color(0.03, 0.05, 0.12),
			"banner_idle": Color(0.06, 0.09, 0.20, 0.95),
			"banner_info": Color(0.10, 0.14, 0.30, 0.95),
			"radius_card": 8,
			"radius_btn": 6,
			"radius_field": 6,
			"border_w": 2,
			"shadow_size": 4,
			"shadow_alpha": 0.4,
			"font_delta": 0,
		},

		# Alias legacy pour configs sauvegardées
		"default": {
			"primary": Color(0.86, 0.14, 0.22),
			"primary_fg": Color(0.98, 0.95, 0.94),
			"accent": Color(0.95, 0.82, 0.78),
			"surface": Color(0.14, 0.05, 0.07),
			"card": Color(0.10, 0.03, 0.05),
			"border": Color(0.42, 0.12, 0.18),
			"muted": Color(0.68, 0.48, 0.52),
			"ok": Color(0.35, 0.78, 0.52),
			"err": Color(0.95, 0.40, 0.42),
			"text": Color(0.98, 0.94, 0.92),
			"hover": Color(0.20, 0.07, 0.10),
			"pressed": Color(0.08, 0.02, 0.04),
			"banner_idle": Color(0.09, 0.03, 0.04, 0.94),
			"banner_info": Color(0.14, 0.05, 0.07, 0.95),
		},
		"sunrise": {
			"primary": Color(0.95, 0.38, 0.18),
			"primary_fg": Color(0.12, 0.05, 0.02),
			"accent": Color(0.98, 0.72, 0.35),
			"surface": Color(0.18, 0.08, 0.05),
			"card": Color(0.13, 0.05, 0.03),
			"border": Color(0.48, 0.22, 0.12),
			"muted": Color(0.72, 0.52, 0.40),
			"ok": Color(0.42, 0.78, 0.45),
			"err": Color(0.92, 0.38, 0.32),
			"text": Color(0.99, 0.94, 0.88),
			"hover": Color(0.24, 0.12, 0.07),
			"pressed": Color(0.10, 0.04, 0.02),
			"banner_idle": Color(0.12, 0.05, 0.03, 0.94),
			"banner_info": Color(0.18, 0.08, 0.05, 0.95),
		},
		"sepia": {
			"primary": Color(0.78, 0.18, 0.26),
			"primary_fg": Color(0.98, 0.96, 0.95),
			"accent": Color(0.55, 0.22, 0.28),
			"surface": Color(0.28, 0.24, 0.23),
			"card": Color(0.22, 0.19, 0.18),
			"border": Color(0.48, 0.32, 0.34),
			"muted": Color(0.68, 0.58, 0.56),
			"ok": Color(0.32, 0.68, 0.48),
			"err": Color(0.88, 0.42, 0.42),
			"text": Color(0.97, 0.94, 0.92),
			"hover": Color(0.34, 0.28, 0.27),
			"pressed": Color(0.18, 0.14, 0.13),
			"banner_idle": Color(0.18, 0.15, 0.14, 0.94),
			"banner_info": Color(0.24, 0.20, 0.19, 0.95),
		},
	}


func _sync_theme_option() -> void:
	if not is_instance_valid(_theme_option):
		return
	for i in range(_theme_option.item_count):
		if str(_theme_option.get_item_metadata(i)) == _ui_theme:
			_theme_option.select(i)
			return


func _on_theme_selected(idx: int) -> void:
	if not is_instance_valid(_theme_option):
		return
	var key := str(_theme_option.get_item_metadata(idx))
	if key == "":
		return
	_apply_theme(key, true)


func _apply_theme(theme_id: String, persist: bool = true) -> void:
	var p: Dictionary
	if theme_id == "custom" or theme_id.begins_with("user:"):
		if theme_id.begins_with("user:"):
			var uname := theme_id.substr(5)
			if _user_themes.has(uname):
				p = _user_themes[uname]
			else:
				p = _snapshot_theme()
				theme_id = "custom"
		else:
			# custom = dernier état édité (snapshot courant ou sauvegardé)
			var saved_custom = _user_themes.get("__active_custom", null)
			if typeof(saved_custom) == TYPE_DICTIONARY:
				p = saved_custom
			else:
				p = _snapshot_theme()
	else:
		var presets := _theme_presets()
		if not presets.has(theme_id):
			theme_id = "circe"
		p = presets[theme_id]
	_ui_theme = theme_id
	_apply_palette_dict(p)
	# FX embarqués dans le preset (user / custom / JSON import)
	# Au boot (persist=false) on applique quand même les flags mais overlays en deferred
	if p.has("fx"):
		_apply_theme_fx(p, persist)
	elif persist and theme_id in ["ps2", "underground", "horror"]:
		# Fallback historique : certains presets force CRT
		_crt_enabled = true
		_crt_motion = true
		if is_instance_valid(_crt_btn):
			_crt_btn.button_pressed = true
		call_deferred("_ensure_crt_overlay")
	_restyle_all()
	if persist:
		_sfx_play("confirm")
		_save_config()


func _apply_palette_dict(p: Dictionary) -> void:
	if p.has("primary"):
		C_PRIMARY = p["primary"] as Color
	if p.has("primary_fg"):
		C_PRIMARY_FG = p["primary_fg"] as Color
	if p.has("accent"):
		C_ACCENT = p["accent"] as Color
	if p.has("surface"):
		C_SURFACE = p["surface"] as Color
	if p.has("card"):
		C_CARD = p["card"] as Color
	if p.has("border"):
		C_BORDER = p["border"] as Color
	if p.has("muted"):
		C_MUTED = p["muted"] as Color
		C_IDLE = C_MUTED
	if p.has("ok"):
		C_OK = p["ok"] as Color
	if p.has("err"):
		C_ERR = p["err"] as Color
	if p.has("text"):
		C_TEXT = p["text"] as Color
	if p.has("hover"):
		C_HOVER_SURFACE = p["hover"] as Color
	if p.has("pressed"):
		C_PRESSED_SURFACE = p["pressed"] as Color
	if p.has("banner_idle"):
		C_BANNER_IDLE = p["banner_idle"] as Color
	if p.has("banner_info"):
		C_BANNER_INFO = p["banner_info"] as Color
	C_WARN = C_PRIMARY
	C_INFO = C_PRIMARY
	C_BUSY = C_PRIMARY
	C_SECTION = C_PRIMARY
	C_BANNER_OK = Color(C_OK.r * 0.35, C_OK.g * 0.35, C_OK.b * 0.35, 0.95)
	C_BANNER_ERR = Color(0.28, 0.12, 0.12, 0.95)
	C_BANNER_WARN = Color(C_PRIMARY.r * 0.35, C_PRIMARY.g * 0.30, C_PRIMARY.b * 0.15, 0.95)
	# Shape params
	if p.has("radius_card"):
		_t_radius_card = int(p["radius_card"])
	if p.has("radius_btn"):
		_t_radius_btn = int(p["radius_btn"])
	if p.has("radius_field"):
		_t_radius_field = int(p["radius_field"])
	if p.has("border_w"):
		_t_border_w = int(p["border_w"])
	if p.has("shadow_size"):
		_t_shadow_size = int(p["shadow_size"])
	if p.has("shadow_alpha"):
		_t_shadow_alpha = float(p["shadow_alpha"])
	if p.has("font_delta"):
		_t_font_delta = int(p["font_delta"])


func _snapshot_theme_fx() -> Dictionary:
	## FX embarqués dans un preset thème (export / user themes).
	return {
		"crt": _crt_enabled,
		"crt_intensity": _crt_intensity,
		"neon": _neon_enabled,
		"neon_intensity": _neon_intensity,
		"predator": _predator_enabled,
		"predator_intensity": _predator_intensity,
		"rain": _rain_enabled,
		"rain_intensity": _rain_intensity,
		"paper": _paper_enabled,
		"paper_intensity": _paper_intensity,
		"arcade": _arcade_copy,
		"sfx": _sfx_enabled,
	}


func _snapshot_theme() -> Dictionary:
	var d := {
		"primary": C_PRIMARY,
		"primary_fg": C_PRIMARY_FG,
		"accent": C_ACCENT,
		"surface": C_SURFACE,
		"card": C_CARD,
		"border": C_BORDER,
		"muted": C_MUTED,
		"ok": C_OK,
		"err": C_ERR,
		"text": C_TEXT,
		"hover": C_HOVER_SURFACE,
		"pressed": C_PRESSED_SURFACE,
		"banner_idle": C_BANNER_IDLE,
		"banner_info": C_BANNER_INFO,
		"radius_card": _t_radius_card,
		"radius_btn": _t_radius_btn,
		"radius_field": _t_radius_field,
		"border_w": _t_border_w,
		"shadow_size": _t_shadow_size,
		"shadow_alpha": _t_shadow_alpha,
		"font_delta": _t_font_delta,
	}
	d["fx"] = _snapshot_theme_fx()
	return d


func _apply_theme_fx(p: Dictionary, apply_now: bool = true) -> void:
	## Applique le bloc "fx" d'un preset (si présent). apply_now = sync overlays UI.
	if p == null or not p.has("fx"):
		return
	var fx = p["fx"]
	if typeof(fx) != TYPE_DICTIONARY:
		return
	if fx.has("crt"):
		_crt_enabled = bool(fx["crt"])
		_crt_motion = _crt_enabled
	if fx.has("crt_intensity"):
		_crt_intensity = clampf(float(fx["crt_intensity"]), 0.05, 1.0)
	if fx.has("neon"):
		_neon_enabled = bool(fx["neon"])
	if fx.has("neon_intensity"):
		_neon_intensity = clampf(float(fx["neon_intensity"]), 0.15, 1.4)
	if fx.has("predator"):
		_predator_enabled = bool(fx["predator"])
	if fx.has("predator_intensity"):
		_predator_intensity = clampf(float(fx["predator_intensity"]), 0.1, 1.0)
	if fx.has("rain"):
		_rain_enabled = bool(fx["rain"])
	if fx.has("rain_intensity"):
		_rain_intensity = clampf(float(fx["rain_intensity"]), 0.1, 1.0)
	if fx.has("paper"):
		_paper_enabled = bool(fx["paper"])
	if fx.has("paper_intensity"):
		_paper_intensity = clampf(float(fx["paper_intensity"]), 0.1, 1.0)
	if fx.has("arcade"):
		_arcade_copy = bool(fx["arcade"])
	if fx.has("sfx"):
		_sfx_enabled = bool(fx["sfx"])
	if not apply_now:
		return
	# Sync boutons + overlays
	if is_instance_valid(_crt_btn):
		_crt_btn.button_pressed = _crt_enabled
		_crt_btn.text = "CRT" if _crt_enabled else "crt"
	if is_instance_valid(_neon_btn):
		_neon_btn.button_pressed = _neon_enabled
		_neon_btn.text = "NEON" if _neon_enabled else "neon"
	if is_instance_valid(_predator_btn):
		_predator_btn.button_pressed = _predator_enabled
		_predator_btn.text = "PREDATOR" if _predator_enabled else "Predator"
	if is_instance_valid(_rain_btn):
		_rain_btn.button_pressed = _rain_enabled
		_rain_btn.text = "RAIN" if _rain_enabled else "Rain"
	if is_instance_valid(_paper_btn):
		_paper_btn.button_pressed = _paper_enabled
		_paper_btn.text = "PAPER" if _paper_enabled else "Paper"
	if is_instance_valid(_arcade_btn):
		_arcade_btn.button_pressed = _arcade_copy
	if is_instance_valid(_sfx_btn):
		_sfx_btn.button_pressed = _sfx_enabled
	_ensure_crt_overlay()
	_ensure_predator_overlay()
	_ensure_rain_overlay()
	_ensure_paper_overlay()
	if _neon_enabled:
		_neon_apply_all()
	_fx_sync_intensity_rows()
	# Sync sliders if present
	if is_instance_valid(_crt_intensity_slider):
		_crt_intensity_slider.value = _crt_intensity
	if is_instance_valid(_neon_slider):
		_neon_slider.value = _neon_intensity
	if is_instance_valid(_fx_panel):
		for pair in [
			["PredatorSlider", _predator_intensity, "PredatorPct"],
			["RainSlider", _rain_intensity, "RainPct"],
			["PaperSlider", _paper_intensity, "PaperPct"],
		]:
			var sl = _fx_panel.find_child(pair[0], true, false)
			if sl and sl is Range:
				(sl as Range).value = float(pair[1])
			var pct = _fx_panel.find_child(pair[2], true, false)
			if pct:
				pct.text = "%d%%" % int(float(pair[1]) * 100.0)
	set_process(_fx_needs_process())
	if _arcade_copy:
		_apply_ui_texts()


func _color_to_html(c: Color) -> String:
	return "#%02x%02x%02x%02x" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0), int(c.a * 255.0)]


func _html_to_color(s: String) -> Color:
	return Color.html(s) if s.begins_with("#") else Color(s)


func _theme_dict_to_json(d: Dictionary) -> String:
	var out := {}
	for k in d.keys():
		var v = d[k]
		if v is Color:
			out[k] = _color_to_html(v)
		else:
			out[k] = v
	return JSON.stringify(out, "\t")


func _theme_dict_from_json(txt: String) -> Dictionary:
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var out := {}
	var color_keys := ["primary", "primary_fg", "accent", "surface", "card", "border", "muted", "ok", "err", "text", "hover", "pressed", "banner_idle", "banner_info"]
	for k in parsed.keys():
		if k in color_keys and typeof(parsed[k]) == TYPE_STRING:
			out[k] = _html_to_color(str(parsed[k]))
		else:
			out[k] = parsed[k]
	return out


# ══════════════════════════════════════════════════════════════════════════════
# ÉDITEUR DE THÈME AVANCÉ
# ══════════════════════════════════════════════════════════════════════════════

const _TE_COLOR_KEYS := [
	["primary", "Primary"], ["primary_fg", "Primary FG"], ["accent", "Accent"],
	["surface", "Surface"], ["card", "Card"], ["border", "Border"],
	["muted", "Muted"], ["text", "Text"], ["ok", "OK"], ["err", "Error"],
	["hover", "Hover"], ["pressed", "Pressed"],
	["banner_idle", "Banner idle"], ["banner_info", "Banner info"],
]

const _TE_SHAPE_KEYS := [
	["radius_card", "Radius card", 0, 32],
	["radius_btn", "Radius btn", 0, 28],
	["radius_field", "Radius field", 0, 24],
	["border_w", "Border width", 0, 6],
	["shadow_size", "Shadow size", 0, 24],
	["font_delta", "Font ±", -4, 8],
]


func _open_theme_editor() -> void:
	if is_instance_valid(_theme_editor_layer):
		_theme_editor_layer.queue_free()
		_theme_editor_layer = null
	_te_color_pickers.clear()
	_te_spins.clear()

	_theme_editor_layer = Control.new()
	_theme_editor_layer.name = "ThemeEditorLayer"
	_theme_editor_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_theme_editor_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_theme_editor_layer.z_index = 280
	add_child(_theme_editor_layer)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.01, 0.03, 0.88)
	_theme_editor_layer.add_child(dim)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_theme_editor_layer.add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	scroll.add_child(root)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(col)

	# Header
	var title := Label.new()
	title.text = tr_ui("theme_edit_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", _ed_font(5))
	title.add_theme_color_override("font_color", C_PRIMARY)
	col.add_child(title)

	var sub := Label.new()
	sub.text = tr_ui("theme_edit_sub")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.modulate = C_MUTED
	sub.add_theme_font_size_override("font_size", _ed_font(-1))
	col.add_child(sub)

	# Base preset + user presets
	var base_row := HBoxContainer.new()
	base_row.add_theme_constant_override("separation", 8)
	col.add_child(base_row)
	var base_lbl := Label.new()
	base_lbl.text = tr_ui("theme_edit_base")
	base_lbl.custom_minimum_size.x = 90
	base_row.add_child(base_lbl)
	var base_opt := OptionButton.new()
	base_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in ["circe", "sakura", "onyx", "ivory", "ember", "matrix", "forest", "ps2", "underground", "chicago30", "gangster90", "gangsta00", "teranga", "wax", "sahel", "savane", "synthwave", "cyberpunk", "steampunk", "horror", "minimal", "pixel", "vaporwave", "manga", "ocean", "brutalist", "western", "comicbook"]:
		base_opt.add_item(tr_ui("theme_%s" % id))
		base_opt.set_item_metadata(base_opt.item_count - 1, id)
	base_opt.item_selected.connect(func(i: int) -> void:
		var id := str(base_opt.get_item_metadata(i))
		_apply_theme(id, false)
		_te_sync_from_current()
	)
	base_row.add_child(base_opt)
	_style_option_button(base_opt)

	# User preset load
	var user_row := HBoxContainer.new()
	user_row.add_theme_constant_override("separation", 8)
	col.add_child(user_row)
	var user_lbl := Label.new()
	user_lbl.text = tr_ui("theme_edit_presets")
	user_lbl.custom_minimum_size.x = 90
	user_row.add_child(user_lbl)
	_te_preset_option = OptionButton.new()
	_te_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_te_refresh_preset_option()
	_te_preset_option.item_selected.connect(_on_te_preset_selected)
	user_row.add_child(_te_preset_option)
	_style_option_button(_te_preset_option)

	# Colors section
	var col_title := Label.new()
	col_title.text = tr_ui("theme_edit_colors")
	col_title.add_theme_color_override("font_color", C_PRIMARY)
	col_title.add_theme_font_size_override("font_size", _ed_font(1))
	col.add_child(col_title)

	var color_grid := GridContainer.new()
	color_grid.columns = 2
	color_grid.add_theme_constant_override("h_separation", 10)
	color_grid.add_theme_constant_override("v_separation", 6)
	color_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(color_grid)

	var snap := _snapshot_theme()
	for pair in _TE_COLOR_KEYS:
		var key: String = pair[0]
		var label_txt: String = pair[1]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lbl := Label.new()
		lbl.text = label_txt
		lbl.custom_minimum_size.x = 88
		lbl.add_theme_font_size_override("font_size", _ed_font(-1))
		row.add_child(lbl)
		var cp := ColorPickerButton.new()
		cp.custom_minimum_size = Vector2(72, 28)
		cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cp.edit_alpha = true
		if snap.has(key) and snap[key] is Color:
			cp.color = snap[key]
		cp.color_changed.connect(_on_te_color_changed.bind(key))
		row.add_child(cp)
		_te_color_pickers[key] = cp
		color_grid.add_child(row)

	# Shape section
	var shape_title := Label.new()
	shape_title.text = tr_ui("theme_edit_shape")
	shape_title.add_theme_color_override("font_color", C_PRIMARY)
	shape_title.add_theme_font_size_override("font_size", _ed_font(1))
	col.add_child(shape_title)

	for pair in _TE_SHAPE_KEYS:
		var key: String = pair[0]
		var label_txt: String = pair[1]
		var mn: int = pair[2]
		var mx: int = pair[3]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = label_txt
		lbl.custom_minimum_size.x = 100
		lbl.add_theme_font_size_override("font_size", _ed_font(-1))
		row.add_child(lbl)
		var sp := SpinBox.new()
		sp.min_value = mn
		sp.max_value = mx
		sp.step = 1
		sp.value = float(snap.get(key, 0))
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.value_changed.connect(_on_te_shape_changed.bind(key))
		row.add_child(sp)
		_te_spins[key] = sp
		col.add_child(row)

	# Shadow alpha
	var alpha_row := HBoxContainer.new()
	alpha_row.add_theme_constant_override("separation", 8)
	var alpha_lbl := Label.new()
	alpha_lbl.text = "Shadow α"
	alpha_lbl.custom_minimum_size.x = 100
	alpha_lbl.add_theme_font_size_override("font_size", _ed_font(-1))
	alpha_row.add_child(alpha_lbl)
	var alpha_sl := HSlider.new()
	alpha_sl.min_value = 0.0
	alpha_sl.max_value = 0.6
	alpha_sl.step = 0.01
	alpha_sl.value = _t_shadow_alpha
	alpha_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alpha_sl.value_changed.connect(func(v: float) -> void:
		_t_shadow_alpha = v
		_restyle_all()
	)
	alpha_row.add_child(alpha_sl)
	col.add_child(alpha_row)

	# FX pack section — embarqués dans le preset nommé / JSON
	_te_fx_checks.clear()
	_te_fx_spins.clear()
	var fx_title := Label.new()
	fx_title.text = tr_ui("theme_edit_fx")
	fx_title.add_theme_color_override("font_color", C_PRIMARY)
	fx_title.add_theme_font_size_override("font_size", _ed_font(1))
	col.add_child(fx_title)
	var fx_hint := Label.new()
	fx_hint.text = tr_ui("theme_edit_fx_hint")
	fx_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fx_hint.modulate = C_MUTED
	fx_hint.add_theme_font_size_override("font_size", _ed_font(-2))
	col.add_child(fx_hint)
	var fx_snap: Dictionary = _snapshot_theme_fx()
	var fx_defs := [
		["crt", "crt_intensity", "CRT", 0.05, 1.0],
		["neon", "neon_intensity", "Neon", 0.15, 1.4],
		["predator", "predator_intensity", "Predator", 0.1, 1.0],
		["rain", "rain_intensity", "Rain", 0.1, 1.0],
		["paper", "paper_intensity", "Paper", 0.1, 1.0],
		["arcade", "", "Arcade", 0.0, 0.0],
		["sfx", "", "SFX", 0.0, 0.0],
	]
	for def in fx_defs:
		var fk: String = def[0]
		var ik: String = def[1]
		var flabel: String = def[2]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var cb := CheckButton.new()
		cb.text = flabel
		cb.button_pressed = bool(fx_snap.get(fk, false))
		cb.toggled.connect(func(on: bool) -> void:
			# Aperçu live dans le dock
			match fk:
				"crt":
					_on_crt_toggled(on)
				"neon":
					_on_neon_toggled(on)
				"predator":
					_on_predator_toggled(on)
				"rain":
					_on_rain_toggled(on)
				"paper":
					_on_paper_toggled(on)
				"arcade":
					_on_arcade_toggled(on)
				"sfx":
					_on_sfx_toggled(on)
		)
		row.add_child(cb)
		_te_fx_checks[fk] = cb
		if ik != "":
			var sl := HSlider.new()
			sl.min_value = float(def[3])
			sl.max_value = float(def[4])
			sl.step = 0.05
			sl.value = float(fx_snap.get(ik, 0.5))
			sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sl.value_changed.connect(func(v: float) -> void:
				match ik:
					"crt_intensity":
						_on_crt_intensity_changed(v)
					"neon_intensity":
						_on_neon_intensity_changed(v)
					"predator_intensity":
						_on_predator_intensity_changed(v)
					"rain_intensity":
						_on_rain_intensity_changed(v)
					"paper_intensity":
						_on_paper_intensity_changed(v)
			)
			row.add_child(sl)
			_te_fx_spins[ik] = sl
		col.add_child(row)

	# Quick actions
	var quick := HFlowContainer.new()
	quick.add_theme_constant_override("h_separation", 8)
	quick.add_theme_constant_override("v_separation", 6)
	col.add_child(quick)
	var actions := [
		["theme_edit_invert", _te_invert_colors],
		["theme_edit_lighten", _te_lighten],
		["theme_edit_darken", _te_darken],
		["theme_edit_saturate", _te_saturate],
		["theme_edit_desaturate", _te_desaturate],
		["theme_edit_random", _te_randomize],
	]
	for a in actions:
		var b := Button.new()
		b.text = tr_ui(a[0])
		b.pressed.connect(a[1])
		quick.add_child(b)
		_style_secondary_button(b)

	# Save named preset
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	col.add_child(save_row)
	_te_name_edit = LineEdit.new()
	_te_name_edit.placeholder_text = tr_ui("theme_edit_name_ph")
	_te_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_te_name_edit)
	_style_line_edit(_te_name_edit)
	var save_btn := Button.new()
	save_btn.text = tr_ui("theme_edit_save")
	save_btn.pressed.connect(_te_save_named)
	save_row.add_child(save_btn)
	_style_primary_button(save_btn)
	var del_btn := Button.new()
	del_btn.text = tr_ui("theme_edit_delete")
	del_btn.pressed.connect(_te_delete_named)
	save_row.add_child(del_btn)
	_style_secondary_button(del_btn)

	# Import / Export
	var io_row := HBoxContainer.new()
	io_row.add_theme_constant_override("separation", 8)
	col.add_child(io_row)
	var export_btn := Button.new()
	export_btn.text = tr_ui("theme_edit_export")
	export_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_btn.pressed.connect(_te_export_json)
	io_row.add_child(export_btn)
	_style_secondary_button(export_btn)
	var import_btn := Button.new()
	import_btn.text = tr_ui("theme_edit_import")
	import_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_btn.pressed.connect(_te_import_json)
	io_row.add_child(import_btn)
	_style_secondary_button(import_btn)

	# Apply as custom + close
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	col.add_child(bottom)
	var apply_btn := Button.new()
	apply_btn.text = tr_ui("theme_edit_apply")
	apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_btn.pressed.connect(_te_apply_custom)
	bottom.add_child(apply_btn)
	_style_success_button(apply_btn)
	var close_btn := Button.new()
	close_btn.text = tr_ui("theme_edit_close")
	close_btn.pressed.connect(_close_theme_editor)
	bottom.add_child(close_btn)
	_style_primary_button(close_btn)

	_theme_editor_layer.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(_theme_editor_layer, "modulate:a", 1.0, 0.15)


func _close_theme_editor() -> void:
	if is_instance_valid(_theme_editor_layer):
		_theme_editor_layer.queue_free()
		_theme_editor_layer = null


func _te_sync_from_current() -> void:
	var snap := _snapshot_theme()
	for k in _te_color_pickers.keys():
		var cp: ColorPickerButton = _te_color_pickers[k]
		if is_instance_valid(cp) and snap.has(k) and snap[k] is Color:
			cp.color = snap[k]
	for k in _te_spins.keys():
		var sp: SpinBox = _te_spins[k]
		if is_instance_valid(sp) and snap.has(k):
			sp.value = float(snap[k])
	var fx: Dictionary = snap.get("fx", _snapshot_theme_fx()) as Dictionary
	if typeof(fx) != TYPE_DICTIONARY:
		fx = _snapshot_theme_fx()
	for k in _te_fx_checks.keys():
		var cb: CheckButton = _te_fx_checks[k]
		if is_instance_valid(cb):
			cb.set_pressed_no_signal(bool(fx.get(k, false)))
	for k in _te_fx_spins.keys():
		var sl = _te_fx_spins[k]
		if is_instance_valid(sl) and fx.has(k):
			sl.value = float(fx[k])


func _on_te_color_changed(color: Color, key: String) -> void:
	var p := {key: color}
	_apply_palette_dict(p)
	# Keep full live state
	match key:
		"primary": C_PRIMARY = color
		"primary_fg": C_PRIMARY_FG = color
		"accent": C_ACCENT = color
		"surface": C_SURFACE = color
		"card": C_CARD = color
		"border": C_BORDER = color
		"muted":
			C_MUTED = color
			C_IDLE = color
		"text": C_TEXT = color
		"ok": C_OK = color
		"err": C_ERR = color
		"hover": C_HOVER_SURFACE = color
		"pressed": C_PRESSED_SURFACE = color
		"banner_idle": C_BANNER_IDLE = color
		"banner_info": C_BANNER_INFO = color
	C_WARN = C_PRIMARY
	C_INFO = C_PRIMARY
	C_BUSY = C_PRIMARY
	C_SECTION = C_PRIMARY
	_restyle_all()


func _on_te_shape_changed(val: float, key: String) -> void:
	match key:
		"radius_card": _t_radius_card = int(val)
		"radius_btn": _t_radius_btn = int(val)
		"radius_field": _t_radius_field = int(val)
		"border_w": _t_border_w = int(val)
		"shadow_size": _t_shadow_size = int(val)
		"font_delta": _t_font_delta = int(val)
	_restyle_all()


func _te_map_colors(fn: Callable) -> void:
	for k in _te_color_pickers.keys():
		var cp: ColorPickerButton = _te_color_pickers[k]
		if is_instance_valid(cp):
			cp.color = fn.call(cp.color)
			_on_te_color_changed(cp.color, k)


func _te_invert_colors() -> void:
	_te_map_colors(func(c: Color) -> Color: return Color(1.0 - c.r, 1.0 - c.g, 1.0 - c.b, c.a))


func _te_lighten() -> void:
	_te_map_colors(func(c: Color) -> Color: return c.lightened(0.08))


func _te_darken() -> void:
	_te_map_colors(func(c: Color) -> Color: return c.darkened(0.08))


func _te_saturate() -> void:
	_te_map_colors(func(c: Color) -> Color:
		var h := c.h
		var s := clampf(c.s * 1.15, 0.0, 1.0)
		var v := c.v
		return Color.from_hsv(h, s, v, c.a)
	)


func _te_desaturate() -> void:
	_te_map_colors(func(c: Color) -> Color:
		return Color.from_hsv(c.h, clampf(c.s * 0.7, 0.0, 1.0), c.v, c.a)
	)


func _te_randomize() -> void:
	var hue := randf()
	var dark := randf() > 0.45
	for k in _te_color_pickers.keys():
		var cp: ColorPickerButton = _te_color_pickers[k]
		if not is_instance_valid(cp):
			continue
		var c: Color
		match k:
			"primary":
				c = Color.from_hsv(hue, 0.75, 0.9 if not dark else 0.85)
			"primary_fg":
				c = Color(0.05, 0.05, 0.06) if not dark else Color(0.95, 0.95, 0.96)
			"accent":
				c = Color.from_hsv(fmod(hue + 0.12, 1.0), 0.55, 0.88)
			"surface":
				c = Color.from_hsv(hue, 0.15, 0.22 if dark else 0.88)
			"card":
				c = Color.from_hsv(hue, 0.12, 0.14 if dark else 0.92)
			"border":
				c = Color.from_hsv(hue, 0.25, 0.35 if dark else 0.7)
			"muted":
				c = Color.from_hsv(hue, 0.1, 0.55)
			"text":
				c = Color(0.95, 0.94, 0.92) if dark else Color(0.12, 0.1, 0.1)
			"ok":
				c = Color(0.3, 0.8, 0.5)
			"err":
				c = Color(0.9, 0.35, 0.35)
			"hover":
				c = Color.from_hsv(hue, 0.18, 0.28 if dark else 0.82)
			"pressed":
				c = Color.from_hsv(hue, 0.2, 0.1 if dark else 0.75)
			"banner_idle":
				c = Color.from_hsv(hue, 0.1, 0.1 if dark else 0.9, 0.94)
			"banner_info":
				c = Color.from_hsv(hue, 0.12, 0.16 if dark else 0.88, 0.95)
			_:
				c = cp.color
		cp.color = c
		_on_te_color_changed(c, k)


func _te_refresh_preset_option() -> void:
	if not is_instance_valid(_te_preset_option):
		return
	_te_preset_option.clear()
	_te_preset_option.add_item("—")
	_te_preset_option.set_item_metadata(0, "")
	for n in _user_themes.keys():
		if str(n).begins_with("__"):
			continue
		_te_preset_option.add_item(str(n))
		_te_preset_option.set_item_metadata(_te_preset_option.item_count - 1, str(n))


func _on_te_preset_selected(idx: int) -> void:
	if not is_instance_valid(_te_preset_option):
		return
	var name := str(_te_preset_option.get_item_metadata(idx))
	if name == "" or not _user_themes.has(name):
		return
	var p: Dictionary = _user_themes[name]
	_apply_palette_dict(p)
	_apply_theme_fx(p, true)
	_restyle_all()
	_te_sync_from_current()
	if is_instance_valid(_te_name_edit):
		_te_name_edit.text = name


func _te_save_named() -> void:
	var name := ""
	if is_instance_valid(_te_name_edit):
		name = _te_name_edit.text.strip_edges()
	if name == "" or name.begins_with("__"):
		_feedback(tr_ui("theme_edit_name_needed"), "warn")
		return
	_user_themes[name] = _snapshot_theme()
	_user_themes["__active_custom"] = _snapshot_theme()
	_te_refresh_preset_option()
	_save_config()
	_feedback(tr_ui("theme_edit_saved") % name, "ok")


func _te_delete_named() -> void:
	var name := ""
	if is_instance_valid(_te_name_edit):
		name = _te_name_edit.text.strip_edges()
	if name == "" or not _user_themes.has(name):
		return
	_user_themes.erase(name)
	_te_refresh_preset_option()
	_save_config()
	_feedback(tr_ui("theme_edit_deleted") % name, "ok")


func _te_apply_custom() -> void:
	_user_themes["__active_custom"] = _snapshot_theme()
	_ui_theme = "custom"
	_sync_theme_option()
	_save_config()
	_feedback(tr_ui("theme_edit_applied"), "ok")
	_close_theme_editor()


func _te_export_json() -> void:
	var json := _theme_dict_to_json(_snapshot_theme())
	DisplayServer.clipboard_set(json)
	_feedback(tr_ui("theme_edit_exported"), "ok")
	_log(tr_ui("theme_edit_exported"), "ok")


func _te_import_json() -> void:
	var txt := DisplayServer.clipboard_get().strip_edges()
	if txt == "":
		_feedback(tr_ui("theme_edit_import_empty"), "warn")
		return
	var d := _theme_dict_from_json(txt)
	if d.is_empty():
		_feedback(tr_ui("theme_edit_import_fail"), "err")
		return
	_apply_palette_dict(d)
	_apply_theme_fx(d, true)
	_restyle_all()
	_te_sync_from_current()
	_feedback(tr_ui("theme_edit_imported"), "ok")


# ══════════════════════════════════════════════════════════════════════════════
# CRT / PS2 / ARCADE / SFX
# ══════════════════════════════════════════════════════════════════════════════


func _on_fx_panel_toggled(on: bool) -> void:
	_fx_panel_open = on
	if is_instance_valid(_fx_panel):
		_fx_panel.visible = on
	if is_instance_valid(_fx_toggle_btn):
		_fx_toggle_btn.text = tr_ui("fx_panel_btn_open") if on else tr_ui("fx_panel_btn")
	_sfx_play("click")


func _fx_sync_intensity_rows() -> void:
	if not is_instance_valid(_fx_panel):
		return
	var crt_row = _fx_panel.find_child("CrtIntensityRow", true, false)
	if crt_row:
		crt_row.visible = _crt_enabled
	var neon_row = _fx_panel.find_child("NeonIntensityRow", true, false)
	if neon_row:
		neon_row.visible = _neon_enabled
	var pred_row = _fx_panel.find_child("PredatorIntensityRow", true, false)
	if pred_row:
		pred_row.visible = _predator_enabled
	var rain_row = _fx_panel.find_child("RainIntensityRow", true, false)
	if rain_row:
		rain_row.visible = _rain_enabled
	var paper_row = _fx_panel.find_child("PaperIntensityRow", true, false)
	if paper_row:
		paper_row.visible = _paper_enabled


func _fx_needs_process() -> bool:
	return _crt_enabled or _neon_enabled or _tag_draw_mode or _predator_enabled or _rain_enabled or _paper_enabled


func _on_crt_toggled(on: bool) -> void:
	_crt_enabled = on
	_crt_motion = on
	_ensure_crt_overlay()
	_fx_sync_intensity_rows()
	if on:
		set_process(true)
		_crt_apply_intensity()
	elif not _fx_needs_process():
		set_process(false)
	_sfx_play("click")
	_save_config()


func _on_arcade_toggled(on: bool) -> void:
	_arcade_copy = on
	_apply_ui_texts()
	_sfx_play("click")
	_save_config()


func _on_sfx_toggled(on: bool) -> void:
	_sfx_enabled = on
	_sfx_play("confirm")
	_save_config()



func _on_neon_toggled(on: bool) -> void:
	_neon_enabled = on
	if is_instance_valid(_neon_btn):
		_neon_btn.text = "NEON" if on else "neon"
	if on:
		set_process(true)
		_fx_sync_intensity_rows()
		_neon_apply_all()
	else:
		_fx_sync_intensity_rows()
		_restyle_all()
		if not _fx_needs_process():
			set_process(false)
	_sfx_play("confirm" if on else "click")
	_save_config()
	_feedback(tr_ui("neon_on") if on else tr_ui("neon_off"), "info" if on else "idle")


func _on_predator_toggled(on: bool) -> void:
	_predator_enabled = on
	if is_instance_valid(_predator_btn):
		_predator_btn.text = "PREDATOR" if on else "Predator"
	_ensure_predator_overlay()
	_fx_sync_intensity_rows()
	if on:
		set_process(true)
	elif not _fx_needs_process():
		set_process(false)
	_sfx_play("confirm" if on else "click")
	_save_config()
	_feedback(tr_ui("predator_on") if on else tr_ui("predator_off"), "info" if on else "idle")


func _on_predator_intensity_changed(v: float) -> void:
	_predator_intensity = clampf(v, 0.1, 1.0)
	if is_instance_valid(_fx_panel):
		var pct = _fx_panel.find_child("PredatorPct", true, false)
		if pct:
			pct.text = "%d%%" % int(_predator_intensity * 100.0)
	_predator_apply_intensity()
	_save_config()


func _on_rain_toggled(on: bool) -> void:
	_rain_enabled = on
	if is_instance_valid(_rain_btn):
		_rain_btn.text = "RAIN" if on else "Rain"
	_ensure_rain_overlay()
	_fx_sync_intensity_rows()
	if on:
		set_process(true)
	elif not _fx_needs_process():
		set_process(false)
	_sfx_play("confirm" if on else "click")
	_save_config()
	_feedback(tr_ui("rain_on") if on else tr_ui("rain_off"), "info" if on else "idle")


func _on_rain_intensity_changed(v: float) -> void:
	_rain_intensity = clampf(v, 0.1, 1.0)
	if is_instance_valid(_fx_panel):
		var pct = _fx_panel.find_child("RainPct", true, false)
		if pct:
			pct.text = "%d%%" % int(_rain_intensity * 100.0)
	_rain_apply_intensity()
	_save_config()


func _on_paper_toggled(on: bool) -> void:
	_paper_enabled = on
	if is_instance_valid(_paper_btn):
		_paper_btn.text = "PAPER" if on else "Paper"
	_ensure_paper_overlay()
	_fx_sync_intensity_rows()
	if on:
		set_process(true)
	elif not _fx_needs_process():
		set_process(false)
	_sfx_play("confirm" if on else "click")
	_save_config()
	_feedback(tr_ui("paper_on") if on else tr_ui("paper_off"), "info" if on else "idle")


func _on_paper_intensity_changed(v: float) -> void:
	_paper_intensity = clampf(v, 0.1, 1.0)
	if is_instance_valid(_fx_panel):
		var pct = _fx_panel.find_child("PaperPct", true, false)
		if pct:
			pct.text = "%d%%" % int(_paper_intensity * 100.0)
	_paper_apply_intensity()
	_save_config()


func _neon_ensure_toolbar() -> void:
	_fx_sync_intensity_rows()
	return



func _on_neon_intensity_changed(v: float) -> void:
	_neon_intensity = clampf(v, 0.15, 1.4)
	if is_instance_valid(_fx_panel):
		var pct = _fx_panel.find_child("NeonPct", true, false)
		if pct:
			pct.text = "%d%%" % int(_neon_intensity * 100.0)
	_neon_apply_all()
	_save_config()


func _neon_color() -> Color:
	## Teinte néon selon thème
	if _ui_theme == "ps2" or _ui_theme == "matrix" or _ui_theme == "pixel":
		return Color(0.15, 1.0, 0.45)
	if _ui_theme == "underground" or _ui_theme == "ember" or _ui_theme == "horror":
		return Color(1.0, 0.2, 0.35) if _ui_theme != "horror" else Color(0.55, 0.95, 0.25)
	if _ui_theme == "circe" or _ui_theme == "sakura":
		return Color(1.0, 0.35, 0.55)
	if _ui_theme == "chicago30" or _ui_theme == "steampunk" or _ui_theme == "teranga" or _ui_theme == "sahel":
		return Color(0.95, 0.75, 0.25)
	if _ui_theme == "wax":
		return Color(0.95, 0.55, 0.10)
	if _ui_theme == "savane":
		return Color(0.55, 0.90, 0.30)
	if _ui_theme == "gangster90":
		return Color(1.0, 0.85, 0.2)
	if _ui_theme == "gangsta00" or _ui_theme == "vaporwave":
		return Color(0.95, 0.45, 0.85)
	if _ui_theme == "synthwave":
		return Color(1.0, 0.25, 0.75)
	if _ui_theme == "cyberpunk":
		return Color(0.0, 0.95, 0.95)
	if _ui_theme == "minimal":
		return Color(0.25, 0.50, 0.95)
	if _ui_theme == "manga" or _ui_theme == "comicbook":
		return Color(1.0, 0.2, 0.2)
	if _ui_theme == "ocean":
		return Color(0.2, 0.85, 0.95)
	if _ui_theme == "brutalist":
		return Color(0.95, 0.45, 0.2)
	if _ui_theme == "western":
		return Color(1.0, 0.7, 0.25)
	return Color(C_PRIMARY.r, C_PRIMARY.g, C_PRIMARY.b)


func _neon_apply_all() -> void:
	if not _neon_enabled:
		return
	var nc := _neon_color()
	var k := clampf(_neon_intensity, 0.15, 1.4)
	# Titre
	if is_instance_valid(_ui_title):
		_ui_title.add_theme_color_override("font_color", nc)
		_ui_title.add_theme_color_override("font_outline_color", Color(nc.r, nc.g, nc.b, 0.85 * k))
		_ui_title.add_theme_constant_override("outline_size", int(4 + 6 * k))
	# Deploy = gros glow
	if is_instance_valid(deploy_btn):
		_neon_style_button(deploy_btn, nc, k, true)
	if is_instance_valid(connect_btn):
		_neon_style_button(connect_btn, nc, k * 0.85, true)
	# Boutons tools
	for b in [_neon_btn, _crt_btn, _tag_btn, _arcade_btn, _sfx_btn]:
		if is_instance_valid(b):
			_neon_style_button(b, nc, k * 0.55, false)
	# Status banner
	if is_instance_valid(_status_banner):
		var sb := _status_banner.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			var s := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
			s.border_color = nc
			s.shadow_color = Color(nc.r, nc.g, nc.b, 0.4 * k)
			s.shadow_size = int(8 + 10 * k)
			_status_banner.add_theme_stylebox_override("panel", s)
	# Toolbar self-glow
	if is_instance_valid(_neon_toolbar):
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = Color(0.04, 0.04, 0.08, 0.94)
		tsb.set_corner_radius_all(8)
		tsb.content_margin_left = 8
		tsb.content_margin_right = 8
		tsb.content_margin_top = 6
		tsb.content_margin_bottom = 6
		tsb.border_width_left = 1
		tsb.border_width_right = 1
		tsb.border_width_top = 1
		tsb.border_width_bottom = 1
		tsb.border_color = nc
		tsb.shadow_color = Color(nc.r, nc.g, nc.b, 0.5 * k)
		tsb.shadow_size = int(8 + 8 * k)
		_neon_toolbar.add_theme_stylebox_override("panel", tsb)


func _neon_style_button(btn: Button, nc: Color, k: float, primary: bool) -> void:
	var normal := StyleBoxFlat.new()
	if primary:
		normal.bg_color = Color(nc.r * 0.25, nc.g * 0.25, nc.b * 0.25, 0.95)
	else:
		normal.bg_color = Color(0.08, 0.08, 0.1, 0.9)
	normal.set_corner_radius_all(_t_radius_btn if _t_radius_btn > 0 else 6)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.border_color = nc
	normal.shadow_color = Color(nc.r, nc.g, nc.b, 0.55 * k)
	normal.shadow_size = int(6 + 12 * k)
	normal.shadow_offset = Vector2.ZERO
	var hover := normal.duplicate() as StyleBoxFlat
	hover.shadow_size = int(10 + 16 * k)
	hover.shadow_color = Color(nc.r, nc.g, nc.b, 0.75 * k)
	hover.bg_color = Color(nc.r * 0.35, nc.g * 0.35, nc.b * 0.35, 0.95)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_color_override("font_color", nc)
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_outline_color", Color(nc.r, nc.g, nc.b, 0.7 * k))
	btn.add_theme_constant_override("outline_size", int(2 + 3 * k))


var _neon_acc: float = 0.0


func _neon_tick(delta: float) -> void:
	if not _neon_enabled:
		return
	# ~15 fps suffisent pour un pulse doux (évite de recréer un StyleBox à chaque frame)
	_neon_acc += delta
	if _neon_acc < 0.066:
		return
	delta = _neon_acc
	_neon_acc = 0.0
	_neon_pulse_t += delta
	var pulse := 0.72 + 0.28 * sin(_neon_pulse_t * 2.4)
	var k := clampf(_neon_intensity, 0.15, 1.4) * pulse
	var nc := _neon_color()
	# Pulse soft sur Deploy + titre (pas restyle complet chaque frame)
	if is_instance_valid(deploy_btn):
		var sb = deploy_btn.get_theme_stylebox("normal")
		if sb is StyleBoxFlat:
			var s := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
			s.shadow_size = int(8 + 14 * k)
			s.shadow_color = Color(nc.r, nc.g, nc.b, 0.5 * k)
			s.border_color = nc
			deploy_btn.add_theme_stylebox_override("normal", s)
	if is_instance_valid(_ui_title):
		_ui_title.add_theme_color_override("font_color", nc.lerp(Color.WHITE, 0.15 * pulse))
		_ui_title.add_theme_constant_override("outline_size", int(3 + 8 * k))



func _ensure_theme_bg() -> void:
	## Calque d'ambiance derrière le contenu — motif procédural selon l'univers.
	if not is_instance_valid(_theme_bg_layer):
		_theme_bg_layer = Control.new()
		_theme_bg_layer.name = "ThemeAmbientBg"
		_theme_bg_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_theme_bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_theme_bg_layer.z_index = -10
		# Insérer tout en bas de la pile (derrière scroll / UI)
		add_child(_theme_bg_layer)
		move_child(_theme_bg_layer, 0)

		_theme_bg_base = ColorRect.new()
		_theme_bg_base.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_theme_bg_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_theme_bg_layer.add_child(_theme_bg_base)

		_theme_bg_pattern = TextureRect.new()
		_theme_bg_pattern.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_theme_bg_pattern.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_theme_bg_pattern.stretch_mode = TextureRect.STRETCH_TILE
		_theme_bg_pattern.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_theme_bg_layer.add_child(_theme_bg_pattern)

		_theme_bg_accent = TextureRect.new()
		_theme_bg_accent.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_theme_bg_accent.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_theme_bg_accent.stretch_mode = TextureRect.STRETCH_TILE
		_theme_bg_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_theme_bg_layer.add_child(_theme_bg_accent)

		_theme_bg_vignette = ColorRect.new()
		_theme_bg_vignette.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_theme_bg_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_theme_bg_vignette.color = Color(0, 0, 0, 0.22)
		_theme_bg_layer.add_child(_theme_bg_vignette)

	_theme_bg_base.color = Color(C_SURFACE.r, C_SURFACE.g, C_SURFACE.b, 1.0)
	var tid := _ui_theme
	if tid.begins_with("user:") or tid == "custom":
		tid = "circe"
	if tid != _theme_bg_id or not is_instance_valid(_theme_bg_pattern.texture):
		_theme_bg_id = tid
		var pack := _make_theme_bg_textures(tid)
		_theme_bg_pattern.texture = pack.get("pattern", null)
		_theme_bg_pattern.modulate = pack.get("pattern_mod", Color(1, 1, 1, 0.35))
		_theme_bg_accent.texture = pack.get("accent", null)
		_theme_bg_accent.modulate = pack.get("accent_mod", Color(1, 1, 1, 0.2))
		_theme_bg_accent.visible = _theme_bg_accent.texture != null
		_theme_bg_vignette.color = pack.get("vignette", Color(0, 0, 0, 0.2))
	else:
		# Même thème : juste resync teinte surface / vignette légère
		_theme_bg_base.color = Color(C_SURFACE.r, C_SURFACE.g, C_SURFACE.b, 1.0)
	_theme_bg_layer.visible = true


func _make_theme_bg_textures(theme_id: String) -> Dictionary:
	## Génère des textures tuilées légères (64×64 max) selon l'univers.
	var out := {
		"pattern": null,
		"pattern_mod": Color(1, 1, 1, 0.32),
		"accent": null,
		"accent_mod": Color(1, 1, 1, 0.18),
		"vignette": Color(0, 0, 0, 0.18),
	}
	match theme_id:
		"synthwave":
			out.pattern = _bg_tex_horizon_grid(Color(1.0, 0.2, 0.7, 0.55), Color(0.2, 0.9, 1.0, 0.4))
			out.accent = _bg_tex_scan_soft(Color(1.0, 0.3, 0.8, 0.35))
			out.pattern_mod = Color(1, 1, 1, 0.4)
			out.vignette = Color(0.15, 0.0, 0.2, 0.35)
		"cyberpunk":
			out.pattern = _bg_tex_tech_grid(Color(0.0, 0.95, 0.95, 0.5), 8)
			out.accent = _bg_tex_rain(Color(0.0, 0.9, 1.0, 0.4))
			out.pattern_mod = Color(1, 1, 1, 0.28)
			out.vignette = Color(0.0, 0.05, 0.1, 0.4)
		"matrix", "ps2":
			out.pattern = _bg_tex_digital_rain(Color(0.15, 1.0, 0.4, 0.55))
			out.pattern_mod = Color(1, 1, 1, 0.3)
			out.vignette = Color(0.0, 0.08, 0.02, 0.35)
		"horror", "underground":
			out.pattern = _bg_tex_grain_tint(Color(0.5, 0.9, 0.2, 0.5) if theme_id == "horror" else Color(1.0, 0.15, 0.2, 0.45))
			out.accent = _bg_tex_scan_soft(Color(0.2, 0.0, 0.0, 0.4))
			out.vignette = Color(0.0, 0.0, 0.0, 0.45)
		"ocean":
			out.pattern = _bg_tex_waves(Color(0.2, 0.75, 0.85, 0.5))
			out.accent = _bg_tex_scan_soft(Color(0.3, 0.9, 0.95, 0.25))
			out.vignette = Color(0.0, 0.05, 0.12, 0.3)
		"western", "teranga", "steampunk", "ember", "sunrise", "sahel":
			out.pattern = _bg_tex_dust(Color(0.9, 0.6, 0.25, 0.45) if theme_id != "sahel" else Color(0.88, 0.55, 0.25, 0.5))
			out.pattern_mod = Color(1, 1, 1, 0.28)
			out.vignette = Color(0.12, 0.05, 0.0, 0.3)
		"wax":
			out.pattern = _bg_tex_wax(Color(0.95, 0.55, 0.08, 0.55), Color(0.15, 0.35, 0.75, 0.5), Color(0.85, 0.2, 0.15, 0.45))
			out.pattern_mod = Color(1, 1, 1, 0.30)
			out.vignette = Color(0.08, 0.04, 0.02, 0.28)
		"savane":
			out.pattern = _bg_tex_soft_noise(Color(0.45, 0.70, 0.28, 0.45))
			out.accent = _bg_tex_dust(Color(0.95, 0.78, 0.22, 0.35))
			out.pattern_mod = Color(1, 1, 1, 0.26)
			out.vignette = Color(0.05, 0.08, 0.02, 0.28)
		"manga":
			out.pattern = _bg_tex_speed_lines(Color(0.95, 0.15, 0.2, 0.4))
			out.pattern_mod = Color(1, 1, 1, 0.22)
			out.vignette = Color(0.0, 0.0, 0.0, 0.35)
		"comicbook":
			out.pattern = _bg_tex_halftone(Color(0.95, 0.2, 0.2, 0.5), Color(0.2, 0.35, 0.9, 0.4))
			out.pattern_mod = Color(1, 1, 1, 0.25)
			out.vignette = Color(0.05, 0.05, 0.15, 0.25)
		"brutalist", "pixel":
			out.pattern = _bg_tex_concrete() if theme_id == "brutalist" else _bg_tex_checker(Color(0.4, 0.7, 0.3, 0.4))
			out.pattern_mod = Color(1, 1, 1, 0.2)
			out.vignette = Color(0.0, 0.0, 0.0, 0.25)
		"vaporwave", "gangsta00":
			out.pattern = _bg_tex_horizon_grid(Color(0.95, 0.45, 0.8, 0.4), Color(0.35, 0.9, 0.88, 0.35))
			out.accent = _bg_tex_scan_soft(Color(0.9, 0.5, 0.85, 0.3))
			out.vignette = Color(0.12, 0.05, 0.15, 0.28)
		"minimal", "ivory":
			out.pattern = _bg_tex_soft_noise(Color(0.5, 0.55, 0.6, 0.2))
			out.pattern_mod = Color(1, 1, 1, 0.12)
			out.vignette = Color(0.9, 0.9, 0.92, 0.08)
		"forest":
			out.pattern = _bg_tex_soft_noise(Color(0.25, 0.55, 0.3, 0.4))
			out.vignette = Color(0.0, 0.08, 0.02, 0.3)
		"chicago30", "gangster90":
			out.pattern = _bg_tex_dust(Color(0.85, 0.7, 0.3, 0.4))
			out.accent = _bg_tex_scan_soft(Color(0.1, 0.1, 0.08, 0.35))
			out.vignette = Color(0.05, 0.04, 0.02, 0.35)
		_:
			# Circe / sakura / onyx / default — grain warm subtil
			out.pattern = _bg_tex_soft_noise(Color(C_PRIMARY.r, C_PRIMARY.g, C_PRIMARY.b, 0.35))
			out.pattern_mod = Color(1, 1, 1, 0.18)
			out.vignette = Color(0.05, 0.0, 0.02, 0.22)
	return out


func _bg_tex_horizon_grid(c1: Color, c2: Color) -> ImageTexture:
	var w := 48
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var t := float(y) / float(h)
		# Lignes d'horizon densifiées vers le bas (perspective synthwave)
		var step := maxi(2, int(2 + t * 10))
		if y % step == 0:
			var col := c1.lerp(c2, t)
			for x in w:
				img.set_pixel(x, y, col)
		# Colonnes verticales
		for x in w:
			if x % 12 == 0:
				var a := 0.25 * (1.0 - t * 0.5)
				img.set_pixel(x, y, Color(c2.r, c2.g, c2.b, a))
	return ImageTexture.create_from_image(img)


func _bg_tex_tech_grid(c: Color, cell: int) -> ImageTexture:
	var w := 64
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			if x % cell == 0 or y % cell == 0:
				var a := c.a * (0.7 if (x % cell == 0 and y % cell == 0) else 0.35)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


func _bg_tex_rain(c: Color) -> ImageTexture:
	var w := 32
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 18:
		var x := randi() % w
		var y0 := randi() % h
		var length := 3 + randi() % 8
		for k in length:
			var yy := (y0 + k) % h
			var a := c.a * (1.0 - float(k) / float(length))
			img.set_pixel(x, yy, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


func _bg_tex_digital_rain(c: Color) -> ImageTexture:
	var w := 40
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in w:
		if randf() > 0.55:
			continue
		var y0 := randi() % h
		var length := 4 + randi() % 12
		for k in length:
			var yy := (y0 + k) % h
			var bright := 1.0 if k == 0 else (0.3 + randf() * 0.5)
			img.set_pixel(x, yy, Color(c.r * bright, c.g * bright, c.b * bright, c.a * bright * 0.8))
	return ImageTexture.create_from_image(img)


func _bg_tex_waves(c: Color) -> ImageTexture:
	var w := 64
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var wave := sin(float(x) * 0.35 + float(y) * 0.2) * 0.5 + 0.5
			var wave2 := sin(float(x) * 0.15 - float(y) * 0.4) * 0.5 + 0.5
			var a := c.a * wave * wave2 * 0.7
			if a > 0.08:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


func _bg_tex_dust(c: Color) -> ImageTexture:
	var w := 48
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var v := randf()
			if v > 0.72:
				var a := (v - 0.72) * 2.5 * c.a
				img.set_pixel(x, y, Color(c.r, c.g * (0.85 + v * 0.15), c.b * 0.7, clampf(a, 0.0, 0.7)))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _bg_tex_speed_lines(c: Color) -> ImageTexture:
	var w := 48
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 14:
		var y := randi() % h
		var thick := 1 + randi() % 2
		var a := c.a * (0.3 + randf() * 0.7)
		for t in thick:
			var yy := mini(h - 1, y + t)
			for x in w:
				# Lignes diagonales type speed lines
				var xx := (x + i * 3) % w
				if (xx + yy) % 5 < 2:
					img.set_pixel(xx, yy, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


func _bg_tex_halftone(c1: Color, c2: Color) -> ImageTexture:
	var w := 32
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cell := 4
	for y in range(0, h, cell):
		for x in range(0, w, cell):
			var col := c1 if ((x / cell) + (y / cell)) % 2 == 0 else c2
			var r := 1 + ((x + y) % 3)
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if dx * dx + dy * dy <= r * r:
						var px := x + cell / 2 + dx
						var py := y + cell / 2 + dy
						if px >= 0 and px < w and py >= 0 and py < h:
							img.set_pixel(px, py, col)
	return ImageTexture.create_from_image(img)


func _bg_tex_concrete() -> ImageTexture:
	var w := 48
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var v := 0.35 + randf() * 0.3
			# Fissures rares
			var crack := 0.0
			if (x + y * 3) % 37 == 0 or (x * 2 + y) % 41 == 0:
				crack = 0.25
			img.set_pixel(x, y, Color(v, v * 0.98, v * 0.95, 0.35 + crack))
	return ImageTexture.create_from_image(img)


func _bg_tex_checker(c: Color) -> ImageTexture:
	var w := 16
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cell := 4
	for y in h:
		for x in w:
			if ((x / cell) + (y / cell)) % 2 == 0:
				img.set_pixel(x, y, c)
			else:
				img.set_pixel(x, y, Color(c.r * 0.5, c.g * 0.5, c.b * 0.5, c.a * 0.5))
	return ImageTexture.create_from_image(img)


func _bg_tex_scan_soft(c: Color) -> ImageTexture:
	var h := 8
	var img := Image.create(4, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in 4:
		img.set_pixel(x, 0, Color(c.r, c.g, c.b, c.a * 0.6))
		img.set_pixel(x, 1, Color(c.r, c.g, c.b, c.a * 0.2))
	return ImageTexture.create_from_image(img)


func _bg_tex_soft_noise(c: Color) -> ImageTexture:
	var w := 32
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var v := randf()
			if v > 0.65:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * (v - 0.5)))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _bg_tex_grain_tint(c: Color) -> ImageTexture:
	## Grain teinté densifié (horror / underground) — 48×48 tuilable
	var w := 48
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var v := randf()
			if v > 0.55:
				var a := (v - 0.55) * 1.8 * c.a
				# Légère variation de teinte pour un grain « film / parasite »
				var tint := 0.85 + randf() * 0.3
				img.set_pixel(x, y, Color(c.r * tint, c.g * tint, c.b * (0.9 + randf() * 0.15), clampf(a, 0.0, 0.85)))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _bg_tex_wax(c1: Color, c2: Color, c3: Color) -> ImageTexture:
	## Motif géométrique type tissu wax / ankara — 48×48
	var w := 48
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cell := 12
	for y in h:
		for x in w:
			var cx := (x / cell) * cell + cell / 2
			var cy := (y / cell) * cell + cell / 2
			var dx := absf(x - cx)
			var dy := absf(y - cy)
			var ring := maxf(dx, dy)
			var col: Color
			if ring < 2.0:
				col = c1
			elif ring < 4.0:
				col = c2
			elif (x / 3 + y / 3) % 2 == 0:
				col = Color(c3.r, c3.g, c3.b, c3.a * 0.55)
			else:
				continue
			img.set_pixel(x, y, col)
	# Bandes diagonales
	for y in h:
		for x in w:
			if (x + y) % 16 < 2 and img.get_pixel(x, y).a < 0.1:
				img.set_pixel(x, y, Color(c1.r, c1.g, c1.b, c1.a * 0.4))
	return ImageTexture.create_from_image(img)


func _ensure_crt_overlay() -> void:
	if not _crt_enabled:
		if is_instance_valid(_crt_layer):
			_crt_layer.visible = false
		return
	if not is_instance_valid(_crt_layer):
		_crt_layer = Control.new()
		_crt_layer.name = "CrtOverlay"
		_crt_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_crt_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crt_layer.z_index = 90
		add_child(_crt_layer)
		# Phosphor RGB subpixels
		_crt_phosphor = TextureRect.new()
		_crt_phosphor.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_crt_phosphor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_crt_phosphor.stretch_mode = TextureRect.STRETCH_TILE
		_crt_phosphor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crt_phosphor.modulate = Color(1, 1, 1, 0.28)
		_crt_layer.add_child(_crt_phosphor)
		# Scanlines denses
		_crt_scan = TextureRect.new()
		_crt_scan.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_crt_scan.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_crt_scan.stretch_mode = TextureRect.STRETCH_TILE
		_crt_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crt_scan.modulate = Color(1, 1, 1, 0.42)
		_crt_layer.add_child(_crt_scan)
		# Grain fort
		_crt_grain = TextureRect.new()
		_crt_grain.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_crt_grain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_crt_grain.stretch_mode = TextureRect.STRETCH_TILE
		_crt_grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crt_grain.modulate = Color(1, 1, 1, 0.22)
		_crt_layer.add_child(_crt_grain)
		# Aberration rouge (décalée)
		_crt_aberr_r = ColorRect.new()
		_crt_aberr_r.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_crt_aberr_r.color = Color(1.0, 0.05, 0.05, 0.06)
		_crt_aberr_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crt_layer.add_child(_crt_aberr_r)
		_crt_aberr_b = ColorRect.new()
		_crt_aberr_b.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_crt_aberr_b.color = Color(0.05, 0.15, 1.0, 0.05)
		_crt_aberr_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crt_layer.add_child(_crt_aberr_b)
		# Vignette CRT (bords noirs)
		_crt_vignette = ColorRect.new()
		_crt_vignette.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_crt_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crt_vignette.color = Color(0, 0, 0, 0)  # drawn via style? use modulate layer
		# Vignette via 4 edges
		for edge in ["top", "bottom", "left", "right"]:
			var e := ColorRect.new()
			e.mouse_filter = Control.MOUSE_FILTER_IGNORE
			e.color = Color(0, 0, 0, 0.55)
			e.set_meta("crt_edge", edge)
			_crt_layer.add_child(e)
		# Rolling bar (bande de refresh)
		_crt_roll = ColorRect.new()
		_crt_roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crt_roll.color = Color(1, 1, 1, 0.07)
		_crt_roll.size = Vector2(400, 28)
		_crt_layer.add_child(_crt_roll)
		_crt_phosphor.texture = _make_phosphor_tex()
		_crt_scan.texture = _make_scanline_tex()
		_crt_grain.texture = _make_grain_tex()
		_crt_layout_vignette()
	_crt_layer.visible = true
	_crt_apply_theme_tint()
	_crt_apply_intensity()
	_crt_layout_vignette()
	# Tags auto off
	if is_instance_valid(_graffiti_layer):
		_graffiti_layer.visible = false
	if is_inside_tree():
		_tag_ensure_canvas()


func _crt_build_toolbar() -> void:
	# Intensité dans le panneau FX uniquement (plus d'overlay flottant)
	_fx_sync_intensity_rows()
	return



func _on_crt_intensity_changed(v: float) -> void:
	_crt_intensity = clampf(v, 0.05, 1.0)
	if is_instance_valid(_fx_panel):
		var pct = _fx_panel.find_child("CrtPct", true, false)
		if pct:
			pct.text = "%d%%" % int(_crt_intensity * 100.0)
	_crt_apply_intensity()
	_save_config()


func _crt_apply_theme_tint() -> void:
	# Couleurs de base (alpha final = base * intensity)
	if not is_instance_valid(_crt_scan):
		return
	if _ui_theme == "ps2":
		_crt_scan.modulate = Color(0.25, 1.0, 0.4, 1.0)
		if is_instance_valid(_crt_phosphor):
			_crt_phosphor.modulate = Color(0.4, 1.0, 0.5, 1.0)
		if is_instance_valid(_crt_grain):
			_crt_grain.modulate = Color(0.6, 1.0, 0.7, 1.0)
	elif _ui_theme == "underground":
		_crt_scan.modulate = Color(1.0, 0.22, 0.18, 1.0)
		if is_instance_valid(_crt_phosphor):
			_crt_phosphor.modulate = Color(1.0, 0.35, 0.25, 1.0)
		if is_instance_valid(_crt_grain):
			_crt_grain.modulate = Color(1.0, 0.5, 0.4, 1.0)
	else:
		_crt_scan.modulate = Color(1, 1, 1, 1.0)
		if is_instance_valid(_crt_phosphor):
			_crt_phosphor.modulate = Color(1, 1, 1, 1.0)
		if is_instance_valid(_crt_grain):
			_crt_grain.modulate = Color(1, 1, 1, 1.0)


func _crt_apply_intensity() -> void:
	## Multiplie les alphas de toutes les couches CRT (0.05 = discret, 1 = max)
	var k := clampf(_crt_intensity, 0.05, 1.0)
	if is_instance_valid(_crt_scan):
		_crt_scan.modulate.a = 0.55 * k
	if is_instance_valid(_crt_phosphor):
		_crt_phosphor.modulate.a = 0.28 * k
	if is_instance_valid(_crt_grain):
		_crt_grain.modulate.a = 0.22 * k
	if is_instance_valid(_crt_aberr_r):
		_crt_aberr_r.color.a = 0.06 * k
	if is_instance_valid(_crt_aberr_b):
		_crt_aberr_b.color.a = 0.05 * k
	if is_instance_valid(_crt_roll):
		_crt_roll.color.a = 0.06 * k
	if is_instance_valid(_crt_layer):
		for ch in _crt_layer.get_children():
			if ch is ColorRect and ch.has_meta("crt_edge"):
				ch.color.a = 0.45 * k


func _crt_layout_vignette() -> void:
	if not is_instance_valid(_crt_layer):
		return
	var w := size.x if size.x > 10.0 else 280.0
	var h := size.y if size.y > 10.0 else 480.0
	var thick_h := maxf(h * 0.12, 28.0)
	var thick_w := maxf(w * 0.10, 18.0)
	for ch in _crt_layer.get_children():
		if not (ch is ColorRect) or not ch.has_meta("crt_edge"):
			continue
		var edge: String = str(ch.get_meta("crt_edge"))
		match edge:
			"top":
				ch.position = Vector2.ZERO
				ch.size = Vector2(w, thick_h)
			"bottom":
				ch.position = Vector2(0, h - thick_h)
				ch.size = Vector2(w, thick_h)
			"left":
				ch.position = Vector2.ZERO
				ch.size = Vector2(thick_w, h)
			"right":
				ch.position = Vector2(w - thick_w, 0)
				ch.size = Vector2(thick_w, h)
	if is_instance_valid(_crt_roll):
		_crt_roll.size = Vector2(w, maxf(h * 0.045, 16.0))


func _crt_tick(delta: float) -> void:
	if not _crt_enabled or not is_instance_valid(_crt_layer) or not _crt_layer.visible:
		return
	_crt_flicker_t += delta
	_crt_roll_y += delta * 70.0
	var h := size.y if size.y > 10.0 else 480.0
	var w := size.x if size.x > 10.0 else 280.0
	# Flicker léger (pas de rand chaque frame → moins de travail CPU)
	var flick := 0.94 + 0.06 * sin(_crt_flicker_t * 31.0)
	if is_instance_valid(_crt_scan):
		_crt_scan.modulate.a = 0.55 * clampf(_crt_intensity, 0.05, 1.0) * flick
	# Grain : shift rare, pas chaque frame
	if is_instance_valid(_crt_grain) and int(_crt_flicker_t * 8.0) % 3 == 0:
		_crt_grain.position = Vector2(sin(_crt_flicker_t * 5.0) * 1.2, cos(_crt_flicker_t * 4.0) * 0.8)
	if is_instance_valid(_crt_roll):
		if _crt_roll_y > h + 40.0:
			_crt_roll_y = -40.0
		_crt_roll.position = Vector2(0, _crt_roll_y)
		var roll_sz := Vector2(w, maxf(h * 0.035, 12.0))
		if _crt_roll.size != roll_sz:
			_crt_roll.size = roll_sz
	if is_instance_valid(_crt_aberr_r):
		_crt_aberr_r.position = Vector2(sin(_crt_flicker_t * 1.7) * 1.2, 0)
	if is_instance_valid(_crt_aberr_b):
		_crt_aberr_b.position = Vector2(cos(_crt_flicker_t * 1.7) * -1.2, 0)











# ── Predator / Rain / Paper overlays ─────────────────────────────────────────

func _ensure_predator_overlay() -> void:
	if not _predator_enabled:
		if is_instance_valid(_predator_layer):
			_predator_layer.visible = false
		return
	if not is_instance_valid(_predator_layer):
		_predator_layer = Control.new()
		_predator_layer.name = "PredatorOverlay"
		_predator_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_predator_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_predator_layer.z_index = 88
		add_child(_predator_layer)
		_predator_heat = TextureRect.new()
		_predator_heat.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_predator_heat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_predator_heat.stretch_mode = TextureRect.STRETCH_TILE
		_predator_heat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_predator_heat.texture = _make_predator_heat_tex()
		_predator_layer.add_child(_predator_heat)
		_predator_scan = ColorRect.new()
		_predator_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_predator_scan.color = Color(1.0, 0.95, 0.4, 0.18)
		_predator_scan.size = Vector2(400, 10)
		_predator_layer.add_child(_predator_scan)
	_predator_layer.visible = true
	_predator_apply_intensity()


func _make_predator_heat_tex() -> ImageTexture:
	## Palette thermique type Predator (bleu froid → vert → jaune → rouge)
	var w := 64
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var n := (sin(x * 0.35 + y * 0.2) * 0.5 + 0.5) * 0.55 + randf() * 0.45
			var c: Color
			if n < 0.25:
				c = Color(0.05, 0.15, 0.55, 0.35 + n * 0.3)
			elif n < 0.45:
				c = Color(0.1, 0.55, 0.35, 0.4)
			elif n < 0.65:
				c = Color(0.85, 0.85, 0.15, 0.45)
			elif n < 0.85:
				c = Color(0.95, 0.45, 0.08, 0.5)
			else:
				c = Color(0.95, 0.12, 0.08, 0.55)
			# Silhouettes floues (blobs chauds)
			var cx := 20 + int(x / 32) * 32
			var cy := 16 + int(y / 32) * 32
			var d := Vector2(x - cx, y - cy).length()
			if d < 10.0:
				c = c.lerp(Color(1.0, 0.2, 0.05, 0.65), 1.0 - d / 10.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _predator_apply_intensity() -> void:
	if not is_instance_valid(_predator_layer):
		return
	var k := clampf(_predator_intensity, 0.1, 1.0)
	if is_instance_valid(_predator_heat):
		_predator_heat.modulate = Color(1, 1, 1, 0.25 + k * 0.55)
	if is_instance_valid(_predator_scan):
		_predator_scan.color.a = 0.08 + k * 0.22


func _predator_tick(delta: float) -> void:
	if not _predator_enabled or not is_instance_valid(_predator_layer) or not _predator_layer.visible:
		return
	_predator_t += delta
	if is_instance_valid(_predator_scan):
		var h := size.y if size.y > 10.0 else 600.0
		var w := size.x if size.x > 10.0 else 320.0
		var pred_sz := Vector2(w, 8.0 + _predator_intensity * 6.0)
		if _predator_scan.size != pred_sz:
			_predator_scan.size = pred_sz
		_predator_scan.position = Vector2(0, fmod(_predator_t * (40.0 + _predator_intensity * 80.0), h + 20.0) - 10.0)
	if is_instance_valid(_predator_heat) and int(_predator_t * 4.0) % 5 == 0:
		# Léger refresh texture pour “bruit thermique”
		_predator_heat.modulate.a = 0.25 + _predator_intensity * 0.55 + sin(_predator_t * 3.0) * 0.04


func _ensure_rain_overlay() -> void:
	if not _rain_enabled:
		if is_instance_valid(_rain_layer):
			_rain_layer.visible = false
		return
	if not is_instance_valid(_rain_layer):
		_rain_layer = Control.new()
		_rain_layer.name = "RainOverlay"
		_rain_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_rain_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rain_layer.z_index = 87
		_rain_layer.clip_contents = true
		add_child(_rain_layer)
		_rain_tex = TextureRect.new()
		_rain_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_rain_tex.stretch_mode = TextureRect.STRETCH_TILE
		_rain_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rain_tex.texture = _make_rain_overlay_tex()
		_rain_layer.add_child(_rain_tex)
	_rain_layer.visible = true
	_rain_apply_intensity()
	_rain_layout()


func _make_rain_overlay_tex() -> ImageTexture:
	var w := 48
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 28:
		var x := randi() % w
		var y0 := randi() % h
		var length := 4 + randi() % 14
		var bright := 0.55 + randf() * 0.45
		for k in length:
			var yy := (y0 + k) % h
			var a := (1.0 - float(k) / float(length)) * 0.55 * bright
			img.set_pixel(x, yy, Color(0.55, 0.88, 1.0, a))
			if x + 1 < w and k % 2 == 0:
				img.set_pixel(x + 1, yy, Color(0.4, 0.75, 0.95, a * 0.35))
	return ImageTexture.create_from_image(img)


func _rain_layout() -> void:
	if not is_instance_valid(_rain_tex):
		return
	var w := size.x if size.x > 10.0 else 320.0
	var h := size.y if size.y > 10.0 else 600.0
	# Tuile plus haute pour scroll vertical
	_rain_tex.position = Vector2(0, -h)
	_rain_tex.size = Vector2(w, h * 2.0 + 20.0)


func _rain_apply_intensity() -> void:
	if is_instance_valid(_rain_tex):
		_rain_tex.modulate = Color(1, 1, 1, 0.2 + clampf(_rain_intensity, 0.1, 1.0) * 0.65)


func _rain_tick(delta: float) -> void:
	if not _rain_enabled or not is_instance_valid(_rain_tex) or not is_instance_valid(_rain_layer) or not _rain_layer.visible:
		return
	var h := size.y if size.y > 10.0 else 600.0
	var speed := 80.0 + _rain_intensity * 160.0
	_rain_offset = fmod(_rain_offset + delta * speed, h)
	_rain_tex.position.y = -h + _rain_offset
	var rain_sz := Vector2(size.x if size.x > 10.0 else 320.0, h * 2.0 + 20.0)
	if _rain_tex.size != rain_sz:
		_rain_tex.size = rain_sz


func _ensure_paper_overlay() -> void:
	if not _paper_enabled:
		if is_instance_valid(_paper_layer):
			_paper_layer.visible = false
		return
	if not is_instance_valid(_paper_layer):
		_paper_layer = Control.new()
		_paper_layer.name = "PaperOverlay"
		_paper_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_paper_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_paper_layer.z_index = 86
		add_child(_paper_layer)
		_paper_tone = TextureRect.new()
		_paper_tone.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_paper_tone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_paper_tone.stretch_mode = TextureRect.STRETCH_TILE
		_paper_tone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_paper_tone.texture = _bg_tex_halftone(Color(0.15, 0.15, 0.18, 0.35), Color(0.55, 0.52, 0.45, 0.25))
		_paper_layer.add_child(_paper_tone)
		_paper_grain = TextureRect.new()
		_paper_grain.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_paper_grain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_paper_grain.stretch_mode = TextureRect.STRETCH_TILE
		_paper_grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_paper_grain.texture = _bg_tex_grain_tint(Color(0.35, 0.32, 0.28, 0.5))
		_paper_layer.add_child(_paper_grain)
	_paper_layer.visible = true
	_paper_apply_intensity()


func _paper_apply_intensity() -> void:
	var k := clampf(_paper_intensity, 0.1, 1.0)
	if is_instance_valid(_paper_tone):
		_paper_tone.modulate = Color(1, 1, 1, 0.15 + k * 0.4)
	if is_instance_valid(_paper_grain):
		_paper_grain.modulate = Color(1, 1, 1, 0.12 + k * 0.35)


func _paper_tick(_delta: float) -> void:
	# Statique — éventuellement un léger pulse grain
	if not _paper_enabled or not is_instance_valid(_paper_grain):
		return
	pass


func _on_tag_mode_toggled(on: bool) -> void:
	_tag_draw_mode = on
	if is_instance_valid(_tag_btn):
		_tag_btn.text = "TAG ✎" if on else "tag"
	if on:
		_tag_ensure_canvas()
		set_process(true)
	else:
		# flush + free mouse capture
		if _tag_dirty and _tag_texture != null and _tag_image != null:
			_tag_texture.update(_tag_image)
			_tag_dirty = false
		_tag_save_image()
		if not _fx_needs_process():
			set_process(false)
	if is_instance_valid(_tag_canvas):
		_tag_canvas.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(_tag_toolbar):
		_tag_toolbar.visible = on
	if on:
		_sfx_play("click")
		_feedback(tr_ui("tag_mode_on"), "info")
	else:
		_tag_drawing = false
		_tag_save_image()
		_feedback(tr_ui("tag_mode_off"), "idle")


func _tag_ensure_canvas() -> void:
	if is_instance_valid(_tag_canvas):
		_tag_resize_image_if_needed()
		return
	_tag_canvas = Control.new()
	_tag_canvas.name = "TagDrawCanvas"
	_tag_canvas.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_tag_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_canvas.z_index = 95
	add_child(_tag_canvas)
	_tag_tex_rect = TextureRect.new()
	_tag_tex_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_tag_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tag_tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_tag_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_canvas.add_child(_tag_tex_rect)
	# Toolbar flottante
	_tag_toolbar = PanelContainer.new()
	_tag_toolbar.visible = false
	_tag_toolbar.z_index = 96
	_tag_toolbar.position = Vector2(8, 48)
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.06, 0.05, 0.06, 0.94)
	tsb.set_corner_radius_all(8)
	tsb.content_margin_left = 8
	tsb.content_margin_right = 8
	tsb.content_margin_top = 6
	tsb.content_margin_bottom = 6
	tsb.border_width_left = 1
	tsb.border_width_right = 1
	tsb.border_width_top = 1
	tsb.border_width_bottom = 1
	tsb.border_color = C_PRIMARY
	_tag_toolbar.add_theme_stylebox_override("panel", tsb)
	_tag_canvas.add_child(_tag_toolbar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_tag_toolbar.add_child(row)
	var hint := Label.new()
	hint.text = tr_ui("tag_hint")
	hint.add_theme_font_size_override("font_size", _ed_font(-2))
	hint.modulate = C_MUTED
	row.add_child(hint)
	# Couleurs spray
	var colors := [
		Color(0.95, 0.15, 0.12, 0.9),
		Color(1.0, 0.45, 0.1, 0.9),
		Color(0.2, 0.95, 0.35, 0.9),
		Color(0.25, 0.7, 1.0, 0.9),
		Color(1.0, 0.95, 0.2, 0.9),
		Color(0.95, 0.95, 0.95, 0.9),
		Color(0.05, 0.05, 0.05, 0.95),
	]
	for c in colors:
		var b := Button.new()
		b.custom_minimum_size = Vector2(22, 22)
		b.tooltip_text = str(c)
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(4)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		var col: Color = c
		b.pressed.connect(func() -> void: _tag_color = col)
		row.add_child(b)
	_tag_size_slider = HSlider.new()
	_tag_size_slider.min_value = 3
	_tag_size_slider.max_value = 36
	_tag_size_slider.value = _tag_brush_size
	_tag_size_slider.custom_minimum_size = Vector2(72, 0)
	_tag_size_slider.value_changed.connect(func(v: float) -> void: _tag_brush_size = v)
	row.add_child(_tag_size_slider)
	var clear_btn := Button.new()
	clear_btn.text = tr_ui("tag_clear")
	clear_btn.pressed.connect(_tag_clear)
	row.add_child(clear_btn)
	_style_secondary_button(clear_btn)
	var done_btn := Button.new()
	done_btn.text = tr_ui("tag_done")
	done_btn.pressed.connect(func() -> void:
		if is_instance_valid(_tag_btn):
			_tag_btn.button_pressed = false
	)
	row.add_child(done_btn)
	_style_primary_button(done_btn)
	# Events souris
	_tag_canvas.gui_input.connect(_on_tag_canvas_input)
	_tag_resize_image_if_needed()
	_tag_load_image()


func _tag_resize_image_if_needed() -> void:
	# Taille = canvas affiché (plafonnée pour la RAM) — ratios 1:1 avec la souris
	var src_w := int(_tag_canvas.size.x) if is_instance_valid(_tag_canvas) and _tag_canvas.size.x > 8 else int(size.x)
	var src_h := int(_tag_canvas.size.y) if is_instance_valid(_tag_canvas) and _tag_canvas.size.y > 8 else int(size.y)
	var w := clampi(src_w, 64, 512)
	var h := clampi(src_h, 64, 960)
	if _tag_image != null and _tag_image.get_width() == w and _tag_image.get_height() == h:
		return
	var old := _tag_image
	_tag_image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_tag_image.fill(Color(0, 0, 0, 0))
	if old != null:
		_tag_image.blit_rect(old, Rect2i(0, 0, mini(old.get_width(), w), mini(old.get_height(), h)), Vector2i.ZERO)
		# libère la ref de l'ancienne image
		old = null
	if _tag_texture == null:
		_tag_texture = ImageTexture.create_from_image(_tag_image)
	else:
		_tag_texture.set_image(_tag_image)
	if is_instance_valid(_tag_tex_rect):
		_tag_tex_rect.texture = _tag_texture


func _on_tag_canvas_input(event: InputEvent) -> void:
	if not _tag_draw_mode:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_tag_drawing = mb.pressed
			if mb.pressed:
				_tag_last_pos = mb.position
				_tag_paint_at(mb.position)
				_tag_canvas.accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# Clic droit = gomme temporaire
			var prev := _tag_color
			_tag_color = Color(0, 0, 0, 0)
			_tag_paint_at(mb.position, true)
			_tag_color = prev
			_tag_canvas.accept_event()
	elif event is InputEventMouseMotion and _tag_drawing:
		var mm := event as InputEventMouseMotion
		_tag_paint_line(_tag_last_pos, mm.position)
		_tag_last_pos = mm.position
		_tag_canvas.accept_event()


func _tag_paint_line(from: Vector2, to: Vector2) -> void:
	var dist := from.distance_to(to)
	var steps := maxi(1, int(dist / maxf(_tag_brush_size * 0.35, 1.0)))
	for i in range(steps + 1):
		var p := from.lerp(to, float(i) / float(steps))
		_tag_paint_at(p)


func _tag_canvas_to_img(pos: Vector2) -> Vector2:
	## Mappe la position souris (canvas plein) → pixels de l'image (souvent plus petite)
	if _tag_image == null:
		return pos
	var cs := Vector2(1, 1)
	if is_instance_valid(_tag_canvas) and _tag_canvas.size.x > 1.0 and _tag_canvas.size.y > 1.0:
		cs = _tag_canvas.size
	elif size.x > 1.0 and size.y > 1.0:
		cs = size
	var iw := float(_tag_image.get_width())
	var ih := float(_tag_image.get_height())
	return Vector2(pos.x / cs.x * iw, pos.y / cs.y * ih)


func _tag_paint_at(pos: Vector2, erase: bool = false) -> void:
	if _tag_image == null:
		_tag_resize_image_if_needed()
	if _tag_image == null:
		return
	var img_pos := _tag_canvas_to_img(pos)
	var scale_b := 1.0
	if is_instance_valid(_tag_canvas) and _tag_canvas.size.x > 1.0:
		scale_b = float(_tag_image.get_width()) / _tag_canvas.size.x
	var r := maxi(1, int(_tag_brush_size * 0.5 * scale_b))
	var cx := int(img_pos.x)
	var cy := int(img_pos.y)
	var w := _tag_image.get_width()
	var h := _tag_image.get_height()
	for oy in range(-r, r + 1):
		for ox in range(-r, r + 1):
			var d := sqrt(float(ox * ox + oy * oy))
			if d > float(r):
				continue
			var x := cx + ox
			var y := cy + oy
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			# Spray : densité aléatoire type aérosol
			var falloff := 1.0 - (d / float(r))
			if randf() > 0.35 + falloff * 0.55:
				continue
			if erase or _tag_color.a < 0.05:
				_tag_image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				var a := clampf(_tag_color.a * falloff * (0.5 + randf() * 0.5), 0.0, 1.0)
				var src := Color(_tag_color.r, _tag_color.g, _tag_color.b, a)
				var dst := _tag_image.get_pixel(x, y)
				# Alpha blend
				var out_a := src.a + dst.a * (1.0 - src.a)
				var out_rgb := Vector3.ZERO
				if out_a > 0.001:
					out_rgb = (Vector3(src.r, src.g, src.b) * src.a + Vector3(dst.r, dst.g, dst.b) * dst.a * (1.0 - src.a)) / out_a
				_tag_image.set_pixel(x, y, Color(out_rgb.x, out_rgb.y, out_rgb.z, out_a))
	# update texture différé — pas à chaque pixel (fuite / spike RAM)
	_tag_dirty = true


func _tag_clear() -> void:
	if _tag_image == null:
		return
	_tag_image.fill(Color(0, 0, 0, 0))
	if _tag_texture:
		_tag_texture.update(_tag_image)
	_tag_save_image()
	_sfx_play("click")
	_feedback(tr_ui("tag_cleared"), "ok")


func _tag_save_image() -> void:
	if _tag_image == null:
		return
	var path := "user://thiossane_graffiti.png"
	_tag_image.save_png(path)


func _tag_load_image() -> void:
	var path := "user://thiossane_graffiti.png"
	if not FileAccess.file_exists(path):
		return
	var img := Image.new()
	if img.load(path) != OK:
		return
	_tag_resize_image_if_needed()
	if _tag_image == null:
		return
	_tag_image.blit_rect(img, Rect2i(0, 0, mini(img.get_width(), _tag_image.get_width()), mini(img.get_height(), _tag_image.get_height())), Vector2i.ZERO)
	if _tag_texture:
		_tag_texture.update(_tag_image)



func _graffiti_tags() -> PackedStringArray:
	## Tags année 2000 / RenderWare / urban underground
	return PackedStringArray([
		"RENDERWARE", "NO CLIP", "2004", "UNDERGROUND", "THIOSSANE",
		"CREW", "PS2", "DVD", "MOD CHIP", "SOFTMOD",
		"NIGHT CITY", "LOW POLY", "16-BIT DREAM", "BURNOUT", "STREETS",
		"TAG UP", "RESPECT", "BUILD OR DIE", "SHIP IT", "ZIP OR DIE",
		"GTA VIBES", "NFS", "SILENT HILL", "CODEC", "SAVE STATE",
		"R* STYLE", "CRASH BANDICOOT", "JAK", "SCEE", "PAL / NTSC",
		"WARA", "BAOBAB", "DAKAR", "TERANGA", "FCFA",
		"∞ LAPS", "GHOST CAR", "NITRO", "DRIFT", "TUNER",
	])


func _graffiti_rebuild() -> void:
	return  # désactivé (RAM)



func _graffiti_spawn_spray(at: Vector2, blood: bool) -> void:
	if not is_instance_valid(_graffiti_layer):
		return
	var tr := TextureRect.new()
	tr.texture = _make_spray_tex(blood)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	var s := randf_range(36, 72)
	tr.size = Vector2(s, s)
	tr.position = at - tr.size * 0.5
	tr.modulate = Color(1, 1, 1, randf_range(0.25, 0.55))
	tr.rotation_degrees = randf_range(-20, 20)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_graffiti_layer.add_child(tr)


func _make_spray_tex(blood: bool = false) -> ImageTexture:
	var key := "blood" if blood else "green"
	if _spray_tex_cache.has(key):
		return _spray_tex_cache[key]
	var w := 24
	var h := 24
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := w * 0.5
	var cy := h * 0.5
	var base := Color(0.95, 0.2, 0.15, 1.0) if blood else Color(0.25, 0.95, 0.4, 1.0)
	for y in h:
		for x in w:
			var dx := (x - cx) / cx
			var dy := (y - cy) / cy
			var d := sqrt(dx * dx + dy * dy)
			if d > 1.0:
				continue
			var n := randf()
			if n > 0.55 + d * 0.4:
				continue
			var a := clampf((1.0 - d) * (0.3 + n * 0.5), 0.0, 0.7)
			img.set_pixel(x, y, Color(base.r, base.g, base.b, a))
	var tex := ImageTexture.create_from_image(img)
	_spray_tex_cache[key] = tex
	return tex


func _graffiti_ensure_timer() -> void:
	# Désactivé — rebuild auto = fuite RAM. Dessin libre via TAG uniquement.
	if is_instance_valid(_graffiti_timer):
		_graffiti_timer.stop()
		_graffiti_timer.queue_free()
		_graffiti_timer = null


func _make_scanline_tex() -> ImageTexture:
	## Scanlines denses type tube cathodique
	var h := 6
	var img := Image.create(4, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in 4:
		img.set_pixel(x, 0, Color(0, 0, 0, 0.85))
		img.set_pixel(x, 1, Color(0, 0, 0, 0.55))
		img.set_pixel(x, 2, Color(0, 0, 0, 0.15))
		img.set_pixel(x, 3, Color(1, 1, 1, 0.04))  # highlight phosphor
		img.set_pixel(x, 4, Color(0, 0, 0, 0.35))
		img.set_pixel(x, 5, Color(0, 0, 0, 0.10))
	return ImageTexture.create_from_image(img)


func _make_phosphor_tex() -> ImageTexture:
	## Sous-pixels R/G/B type grille aperture
	var img := Image.create(3, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(1.0, 0.12, 0.10, 0.55))
	img.set_pixel(1, 0, Color(0.12, 1.0, 0.18, 0.55))
	img.set_pixel(2, 0, Color(0.15, 0.25, 1.0, 0.55))
	return ImageTexture.create_from_image(img)


func _make_grain_tex() -> ImageTexture:
	# 32x32 suffit (tuilé) — 96x96 pixel-by-pixel était trop cher
	var w := 32
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var v := randf()
			var a := 0.0
			if v > 0.6:
				a = (v - 0.6) * 1.2
			img.set_pixel(x, y, Color(v, v * 0.95, v * 0.9, clampf(a, 0.0, 0.65)))
	return ImageTexture.create_from_image(img)


func _graffiti_burst_celebrate() -> void:
	return  # désactivé (RAM)



func _crt_flash_glitch() -> void:
	## Flash + décalage horizontal type CRT (remplace confettis).
	var parent: Control = _celeb_layer if is_instance_valid(_celeb_layer) else self
	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	flash.color = Color(C_PRIMARY.r, C_PRIMARY.g, C_PRIMARY.b, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 40
	parent.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.7, 0.04)
	tw.tween_property(flash, "color:a", 0.0, 0.2)
	tw.tween_callback(flash.queue_free)
	# Glitch bars
	for i in 6:
		var bar := ColorRect.new()
		bar.color = Color(C_PRIMARY.r, C_PRIMARY.g, C_PRIMARY.b, 0.35)
		bar.size = Vector2(size.x + 20, randf_range(2, 8))
		bar.position = Vector2(randf_range(-12, 12), randf_range(0, maxf(size.y, 40)))
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.z_index = 41
		parent.add_child(bar)
		var tb := create_tween()
		tb.tween_property(bar, "position:x", bar.position.x + randf_range(-30, 30), 0.12)
		tb.parallel().tween_property(bar, "modulate:a", 0.0, 0.18)
		tb.tween_callback(bar.queue_free)
	# Shake dock
	var base := position
	var sh := create_tween()
	for j in 5:
		sh.tween_property(self, "position", base + Vector2(randf_range(-4, 4), randf_range(-2, 2)), 0.03)
	sh.tween_property(self, "position", base, 0.05)
	_sfx_play("ship")


func _sfx_play(kind: String = "click") -> void:
	if not _sfx_enabled:
		return
	if not is_instance_valid(_sfx_player):
		_sfx_player = AudioStreamPlayer.new()
		_sfx_player.name = "ArcadeSfx"
		_sfx_player.volume_db = -10.0
		add_child(_sfx_player)
	var stream := _sfx_make_stream(kind)
	if stream == null:
		return
	_sfx_player.stream = stream
	_sfx_player.play()


func _sfx_make_stream(kind: String) -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.06
	var freq := 440.0
	match kind:
		"confirm":
			duration = 0.12
			freq = 660.0
		"ship":
			duration = 0.22
			freq = 523.25
		"error":
			duration = 0.15
			freq = 180.0
		_:
			duration = 0.05
			freq = 520.0
	var n := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / float(sample_rate)
		var f := freq
		if kind == "ship":
			f = 523.25 if t < 0.1 else 784.0
		elif kind == "error":
			f = 200.0 - t * 80.0
		var env := 1.0 - (t / duration)
		var sample := int(clampf(sin(t * f * TAU) * env * 0.35, -1.0, 1.0) * 32767.0)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


func _restyle_all() -> void:
	## Réapplique les styles après un changement de thème.
	_ensure_theme_bg()
	if is_instance_valid(_ui_title):
		_ui_title.add_theme_color_override("font_color", C_PRIMARY)
	if is_instance_valid(_lang_btn):
		_style_secondary_button(_lang_btn)
	if is_instance_valid(_coffee_btn):
		_style_secondary_button(_coffee_btn)
	if is_instance_valid(_theme_option):
		_style_option_button(_theme_option)
	if is_instance_valid(_theme_edit_btn):
		_style_secondary_button(_theme_edit_btn)
	if is_instance_valid(_crt_btn):
		_style_secondary_button(_crt_btn)
	if is_instance_valid(_neon_btn):
		_style_secondary_button(_neon_btn)
	if is_instance_valid(_arcade_btn):
		_style_secondary_button(_arcade_btn)
	if is_instance_valid(_sfx_btn):
		_style_secondary_button(_sfx_btn)
	if is_instance_valid(_tag_btn):
		_style_secondary_button(_tag_btn)
	if _crt_enabled:
		_ensure_crt_overlay()
	if _neon_enabled:
		call_deferred("_neon_apply_all")
	if is_instance_valid(connect_btn):
		_style_primary_button(connect_btn)
	if is_instance_valid(_logout_btn):
		_style_secondary_button(_logout_btn)
	if is_instance_valid(refresh_games_btn):
		_style_secondary_button(refresh_games_btn)
	if is_instance_valid(create_game_btn):
		_style_primary_button(create_game_btn)
	if is_instance_valid(deploy_btn):
		_style_success_button(deploy_btn)
	if is_instance_valid(redeploy_btn):
		_style_secondary_button(redeploy_btn)
	if is_instance_valid(resubmit_btn):
		_style_secondary_button(resubmit_btn)
	if is_instance_valid(_refresh_presets_btn):
		_style_secondary_button(_refresh_presets_btn)
	if is_instance_valid(share_generate_btn):
		_style_primary_button(share_generate_btn)
	if is_instance_valid(share_copy_link_btn):
		_style_secondary_button(share_copy_link_btn)
	if is_instance_valid(_copy_store_btn):
		_style_secondary_button(_copy_store_btn)
	if is_instance_valid(_copy_discord_btn):
		_style_secondary_button(_copy_discord_btn)
	if is_instance_valid(_copy_whatsapp_btn):
		_style_secondary_button(_copy_whatsapp_btn)
	if is_instance_valid(_hist_label):
		_hist_label.add_theme_color_override("font_color", C_SECTION)
	if is_instance_valid(share_stats_btn):
		_style_secondary_button(share_stats_btn)
	if is_instance_valid(mkt_analytics_btn):
		_style_secondary_button(mkt_analytics_btn)
	if is_instance_valid(_clear_log_btn):
		_style_secondary_button(_clear_log_btn)
	if is_instance_valid(api_base_edit):
		_style_line_edit(api_base_edit)
	if is_instance_valid(email_edit):
		_style_line_edit(email_edit)
	if is_instance_valid(password_edit):
		_style_line_edit(password_edit)
	if is_instance_valid(title_edit):
		_style_line_edit(title_edit)
	if is_instance_valid(version_edit):
		_style_line_edit(version_edit)
	if is_instance_valid(release_edit):
		_style_line_edit(release_edit)
	if is_instance_valid(cover_edit):
		_style_line_edit(cover_edit)
	if is_instance_valid(store_base_edit):
		_style_line_edit(store_base_edit)
	if is_instance_valid(share_label_edit):
		_style_line_edit(share_label_edit)
	if is_instance_valid(campaign_edit):
		_style_line_edit(campaign_edit)
	if is_instance_valid(channel_edit):
		_style_line_edit(channel_edit)
	if is_instance_valid(share_url_edit):
		_style_line_edit(share_url_edit)
	if is_instance_valid(desc_edit):
		_style_text_edit(desc_edit)
	if is_instance_valid(log_edit):
		_style_text_edit(log_edit)
	if is_instance_valid(game_option):
		_style_option_button(game_option)
	if is_instance_valid(category_option):
		_style_option_button(category_option)
	if is_instance_valid(preset_web):
		_style_option_button(preset_web)
	if is_instance_valid(preset_windows):
		_style_option_button(preset_windows)
	if is_instance_valid(preset_android):
		_style_option_button(preset_android)
	if is_instance_valid(free_check):
		_style_checkbox(free_check)
	if is_instance_valid(demo_check):
		_style_checkbox(demo_check)
	if is_instance_valid(browser_check):
		_style_checkbox(browser_check)
	if is_instance_valid(share_force_check):
		_style_checkbox(share_force_check)
	if is_instance_valid(_cat_label):
		_cat_label.add_theme_color_override("font_color", C_MUTED)
	if is_instance_valid(_price_label):
		_price_label.add_theme_color_override("font_color", C_MUTED)
	if is_instance_valid(_opt_label):
		_opt_label.add_theme_color_override("font_color", C_MUTED)
	if is_instance_valid(_log_title):
		_log_title.add_theme_color_override("font_color", C_SECTION)
	if is_instance_valid(_footer_label):
		_footer_label.modulate = C_MUTED
	if is_instance_valid(_onboarding_panel):
		var ob_sb := StyleBoxFlat.new()
		ob_sb.bg_color = Color(C_CARD.r, C_CARD.g, C_CARD.b, 0.98)
		ob_sb.set_corner_radius_all(12)
		ob_sb.content_margin_left = 14
		ob_sb.content_margin_right = 14
		ob_sb.content_margin_top = 12
		ob_sb.content_margin_bottom = 12
		ob_sb.border_width_left = 1
		ob_sb.border_width_right = 1
		ob_sb.border_width_top = 1
		ob_sb.border_width_bottom = 1
		ob_sb.border_color = C_PRIMARY
		_onboarding_panel.add_theme_stylebox_override("panel", ob_sb)
	if is_instance_valid(_onboarding_title):
		_onboarding_title.add_theme_color_override("font_color", C_PRIMARY)
	if is_instance_valid(_onboarding_skip_btn):
		_style_secondary_button(_onboarding_skip_btn)
	if is_instance_valid(_onboarding_dismiss_btn):
		_style_primary_button(_onboarding_dismiss_btn)
	for b in _onboarding_step_btns:
		if is_instance_valid(b):
			_style_secondary_button(b)
	if is_instance_valid(step_label):
		step_label.modulate = C_MUTED
	if is_instance_valid(share_stats_label):
		share_stats_label.modulate = C_MUTED
	if is_instance_valid(mkt_sales_label):
		mkt_sales_label.modulate = C_MUTED
	if is_instance_valid(build_limit_label):
		build_limit_label.modulate = C_MUTED
	# Cartes de section
	for sec in [_sec_conn, _sec_game, _sec_fiche, _sec_plat, _sec_deploy, _sec_share, _sec_support, _sec_prog]:
		if is_instance_valid(sec) and sec is PanelContainer:
			(sec as PanelContainer).add_theme_stylebox_override("panel", _make_card_style())
			if sec.has_meta("header_btn"):
				var hb: Button = sec.get_meta("header_btn")
				if is_instance_valid(hb):
					_style_section_header(hb)
					_refresh_section_header(hb)
	# Badges notif : couleur adaptée au thème
	_restyle_section_badges()
	# Bannière
	if is_instance_valid(_status_banner):
		var sb := StyleBoxFlat.new()
		sb.bg_color = C_BANNER_IDLE
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_color = C_BORDER
		_status_banner.add_theme_stylebox_override("panel", sb)
	if is_instance_valid(_celeb_share):
		_style_secondary_button(_celeb_share)
	if is_instance_valid(_celeb_dismiss):
		_style_primary_button(_celeb_dismiss)
	# Tenue mascotte selon thème
	_mascot_rebuild_outfit()




func _mascot_rebuild_outfit() -> void:
	## Accessoires + teinte selon le thème UI actif.
	if not is_instance_valid(_mascot_outfit):
		return
	for c in _mascot_outfit.get_children():
		c.queue_free()
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color.WHITE
	match _ui_theme:
		"matrix":
			_mascot_outfit_matrix()
		"forest":
			_mascot_outfit_forest()
		"ember", "sunrise":
			_mascot_outfit_disco()
		"western", "chicago30":
			_mascot_outfit_western()
		"horror":
			_mascot_outfit_horror()
		"cyberpunk", "underground":
			_mascot_outfit_cyber()
		"synthwave", "vaporwave", "gangsta00":
			_mascot_outfit_synth()
		"steampunk":
			_mascot_outfit_steampunk()
		"pixel", "ps2":
			_mascot_outfit_pixel()
		"ocean":
			_mascot_outfit_ocean()
		"manga", "comicbook":
			_mascot_outfit_manga()
		"teranga":
			_mascot_outfit_teranga()
		"wax":
			_mascot_outfit_wax()
		"sahel":
			_mascot_outfit_sahel()
		"savane":
			_mascot_outfit_savane()
		"gangster90":
			_mascot_outfit_gangster()
		"brutalist", "minimal":
			if is_instance_valid(_mascot_tex):
				_mascot_tex.modulate = Color(0.92, 0.92, 0.94)
		"circe", "onyx":
			_mascot_outfit_default()
		"sakura":
			if is_instance_valid(_mascot_tex):
				_mascot_tex.modulate = Color(1.08, 0.92, 0.96)
		"ivory", "sepia":
			if is_instance_valid(_mascot_tex):
				_mascot_tex.modulate = Color(1.05, 0.98, 0.95)
		_:
			# Identité Thiossane par défaut (hors thèmes très stylisés)
			_mascot_outfit_default()


func _mascot_box_size() -> Vector2:
	var box_w := MASCOT_W
	var box_h := MASCOT_H_LION
	if is_instance_valid(_mascot_sprite_box) and _mascot_sprite_box.custom_minimum_size.x > 4:
		box_w = _mascot_sprite_box.custom_minimum_size.x
		box_h = _mascot_sprite_box.custom_minimum_size.y
	return Vector2(box_w, box_h)


func _mascot_add_tex_rect(parent: Control, tex: Texture2D, pos: Vector2, sz: Vector2, rot: float = 0.0, z: int = 1) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.position = pos
	tr.size = sz
	tr.pivot_offset = sz * 0.5
	tr.rotation_degrees = rot
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.z_index = z
	parent.add_child(tr)
	return tr


func _mascot_make_image(w: int, h: int, fill: Callable) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	fill.call(img)
	return ImageTexture.create_from_image(img)


func _mascot_outfit_matrix() -> void:
	## Lunettes néon vert Matrix
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(0.75, 1.05, 0.80)
	var box_w := MASCOT_W
	var box_h := MASCOT_H_LION
	if is_instance_valid(_mascot_sprite_box) and _mascot_sprite_box.custom_minimum_size.x > 4:
		box_w = _mascot_sprite_box.custom_minimum_size.x
		box_h = _mascot_sprite_box.custom_minimum_size.y
	var glasses := _mascot_make_image(80, 28, func(img: Image) -> void:
		var frame := Color(0.15, 0.95, 0.35, 0.95)
		var lens := Color(0.05, 0.35, 0.12, 0.55)
		var glow := Color(0.2, 1.0, 0.4, 0.25)
		for y in range(4, 24):
			for x in range(4, 34):
				var dx := (x - 19) / 14.0
				var dy := (y - 14) / 9.0
				var d2 := dx * dx + dy * dy
				if d2 <= 1.0:
					img.set_pixel(x, y, lens if d2 < 0.72 else frame)
				elif d2 <= 1.25:
					img.set_pixel(x, y, glow)
		for y in range(4, 24):
			for x in range(46, 76):
				var dx := (x - 61) / 14.0
				var dy := (y - 14) / 9.0
				var d2 := dx * dx + dy * dy
				if d2 <= 1.0:
					img.set_pixel(x, y, lens if d2 < 0.72 else frame)
				elif d2 <= 1.25:
					img.set_pixel(x, y, glow)
		for y in range(12, 16):
			for x in range(34, 46):
				img.set_pixel(x, y, frame)
		for y in range(13, 15):
			for x in range(0, 5):
				img.set_pixel(x, y, frame)
			for x in range(75, 80):
				img.set_pixel(x, y, frame)
	)
	_mascot_add_tex_rect(_mascot_outfit, glasses, Vector2(box_w * 0.14, box_h * 0.28), Vector2(box_w * 0.72, box_h * 0.18), 0.0, 2)


func _mascot_outfit_forest() -> void:
	## Chapeau de paille + foulard campagne
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(0.95, 1.05, 0.90)
	var box_w := MASCOT_W
	var box_h := MASCOT_H_LION
	if is_instance_valid(_mascot_sprite_box) and _mascot_sprite_box.custom_minimum_size.x > 4:
		box_w = _mascot_sprite_box.custom_minimum_size.x
		box_h = _mascot_sprite_box.custom_minimum_size.y
	var hat := _mascot_make_image(96, 40, func(img: Image) -> void:
		var straw := Color(0.82, 0.68, 0.28, 0.95)
		var dark := Color(0.55, 0.42, 0.15, 0.95)
		var band := Color(0.25, 0.45, 0.22, 0.95)
		for y in range(22, 34):
			for x in range(2, 94):
				var t := absf((x - 48) / 46.0)
				if t < 1.0 - (y - 22) * 0.02:
					img.set_pixel(x, y, straw if (x + y) % 3 != 0 else dark)
		for y in range(4, 24):
			for x in range(22, 74):
				var t := absf((x - 48) / 26.0)
				if t < 1.0 - (y - 4) * 0.01:
					img.set_pixel(x, y, straw if (x + y * 2) % 4 != 0 else dark)
		for y in range(18, 23):
			for x in range(20, 76):
				if img.get_pixel(x, y).a > 0.1:
					img.set_pixel(x, y, band)
	)
	_mascot_add_tex_rect(_mascot_outfit, hat, Vector2(box_w * 0.02, box_h * -0.02), Vector2(box_w * 0.96, box_h * 0.32), -4.0, 2)
	var scarf := _mascot_make_image(64, 36, func(img: Image) -> void:
		var c1 := Color(0.55, 0.22, 0.18, 0.9)
		var c2 := Color(0.75, 0.55, 0.25, 0.9)
		for y in range(4, 32):
			for x in range(8, 56):
				var wave := sin(x * 0.35 + y * 0.2) * 3.0
				if absf(x - 32) < 18 + wave - y * 0.15:
					img.set_pixel(x, y, c1 if (x / 4 + y / 3) % 2 == 0 else c2)
	)
	_mascot_add_tex_rect(_mascot_outfit, scarf, Vector2(box_w * 0.18, box_h * 0.58), Vector2(box_w * 0.64, box_h * 0.28), 0.0, 1)


func _mascot_outfit_disco() -> void:
	## Lunettes de soleil 90s + veste disco paillettes
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(1.08, 0.95, 1.05)
	var box_w := MASCOT_W
	var box_h := MASCOT_H_LION
	if is_instance_valid(_mascot_sprite_box) and _mascot_sprite_box.custom_minimum_size.x > 4:
		box_w = _mascot_sprite_box.custom_minimum_size.x
		box_h = _mascot_sprite_box.custom_minimum_size.y
	var shades := _mascot_make_image(84, 26, func(img: Image) -> void:
		var frame := Color(0.95, 0.35, 0.75, 0.98)
		var lens := Color(0.15, 0.05, 0.25, 0.75)
		var shine := Color(1.0, 0.85, 0.95, 0.45)
		for y in range(3, 23):
			for x in range(2, 38):
				var dx := (x - 20) / 16.0
				var dy := (y - 13) / 8.0
				var d2 := dx * dx + dy * dy
				if d2 <= 1.05:
					img.set_pixel(x, y, frame if d2 > 0.78 else lens)
					if dx < -0.3 and dy < -0.2 and d2 < 0.5:
						img.set_pixel(x, y, shine)
			for x in range(46, 82):
				var dx := (x - 64) / 16.0
				var dy := (y - 13) / 8.0
				var d2 := dx * dx + dy * dy
				if d2 <= 1.05:
					img.set_pixel(x, y, frame if d2 > 0.78 else lens)
					if dx < -0.3 and dy < -0.2 and d2 < 0.5:
						img.set_pixel(x, y, shine)
		for y in range(11, 15):
			for x in range(38, 46):
				img.set_pixel(x, y, frame)
	)
	_mascot_add_tex_rect(_mascot_outfit, shades, Vector2(box_w * 0.10, box_h * 0.26), Vector2(box_w * 0.80, box_h * 0.17), 0.0, 2)
	var jacket := _mascot_make_image(72, 40, func(img: Image) -> void:
		var base := Color(0.45, 0.12, 0.55, 0.88)
		var spark := Color(1.0, 0.85, 0.2, 0.95)
		var pink := Color(0.95, 0.3, 0.7, 0.9)
		for y in range(2, 38):
			for x in range(4, 68):
				var edge := absf(x - 36) / 32.0
				if edge < 0.95 - y * 0.008:
					var c := base
					if (x * 7 + y * 13) % 11 == 0:
						c = spark
					elif (x + y) % 9 == 0:
						c = pink
					img.set_pixel(x, y, c)
		for y in range(2, 18):
			for x in range(8, 18):
				if x + y < 28:
					img.set_pixel(x, y, Color(0.95, 0.75, 0.2, 0.95))
			for x in range(54, 64):
				if (72 - x) + y < 28:
					img.set_pixel(x, y, Color(0.95, 0.75, 0.2, 0.95))
	)
	_mascot_add_tex_rect(_mascot_outfit, jacket, Vector2(box_w * 0.14, box_h * 0.55), Vector2(box_w * 0.72, box_h * 0.38), 0.0, 1)


func _mascot_outfit_western() -> void:
	## Chapeau cowboy + bandana
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(1.08, 0.98, 0.88)
	var sz := _mascot_box_size()
	var box_w := sz.x
	var box_h := sz.y
	var hat := _mascot_make_image(100, 44, func(img: Image) -> void:
		var felt := Color(0.42, 0.28, 0.14, 0.96)
		var dark := Color(0.22, 0.14, 0.06, 0.96)
		var band := Color(0.75, 0.55, 0.20, 0.95)
		# Bord large
		for y in range(26, 40):
			for x in range(2, 98):
				var t := absf((x - 50) / 48.0)
				if t < 1.0 - (y - 26) * 0.015:
					img.set_pixel(x, y, felt if (x + y) % 5 != 0 else dark)
		# Couronne
		for y in range(4, 28):
			for x in range(28, 72):
				var t := absf((x - 50) / 22.0)
				if t < 1.0 - (y - 4) * 0.012:
					img.set_pixel(x, y, felt if (x * 2 + y) % 6 != 0 else dark)
		# Bandeau
		for y in range(22, 27):
			for x in range(26, 74):
				if img.get_pixel(x, y).a > 0.1:
					img.set_pixel(x, y, band)
	)
	_mascot_add_tex_rect(_mascot_outfit, hat, Vector2(box_w * -0.02, box_h * -0.06), Vector2(box_w * 1.04, box_h * 0.36), -3.0, 2)
	var bandana := _mascot_make_image(56, 28, func(img: Image) -> void:
		var red := Color(0.75, 0.18, 0.15, 0.9)
		var dark := Color(0.45, 0.10, 0.08, 0.9)
		for y in range(4, 24):
			for x in range(6, 50):
				var wave := sin(x * 0.4) * 2.0
				if absf(x - 28) < 16 + wave - y * 0.2:
					img.set_pixel(x, y, red if (x / 3 + y / 2) % 2 == 0 else dark)
	)
	_mascot_add_tex_rect(_mascot_outfit, bandana, Vector2(box_w * 0.22, box_h * 0.58), Vector2(box_w * 0.56, box_h * 0.22), 0.0, 1)


func _mascot_outfit_horror() -> void:
	## Yeux rouges + ombre / masque léger
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(0.85, 0.92, 0.80)
	var sz := _mascot_box_size()
	var box_w := sz.x
	var box_h := sz.y
	var glow := _mascot_make_image(72, 24, func(img: Image) -> void:
		var red := Color(0.95, 0.15, 0.12, 0.85)
		var core := Color(1.0, 0.45, 0.2, 0.95)
		for y in range(4, 20):
			for x in range(6, 30):
				var dx := (x - 18) / 12.0
				var dy := (y - 12) / 7.0
				var d2 := dx * dx + dy * dy
				if d2 <= 1.0:
					img.set_pixel(x, y, core if d2 < 0.35 else red)
			for x in range(42, 66):
				var dx := (x - 54) / 12.0
				var dy := (y - 12) / 7.0
				var d2 := dx * dx + dy * dy
				if d2 <= 1.0:
					img.set_pixel(x, y, core if d2 < 0.35 else red)
	)
	_mascot_add_tex_rect(_mascot_outfit, glow, Vector2(box_w * 0.14, box_h * 0.30), Vector2(box_w * 0.72, box_h * 0.16), 0.0, 2)
	var shadow := _mascot_make_image(80, 36, func(img: Image) -> void:
		var ink := Color(0.05, 0.08, 0.04, 0.55)
		for y in range(2, 34):
			for x in range(4, 76):
				var edge := absf(x - 40) / 36.0
				if edge < 0.9 - y * 0.01 and randf() > 0.35:
					img.set_pixel(x, y, ink)
	)
	_mascot_add_tex_rect(_mascot_outfit, shadow, Vector2(box_w * 0.10, box_h * 0.52), Vector2(box_w * 0.80, box_h * 0.32), 0.0, 1)


func _mascot_outfit_cyber() -> void:
	## Visor cyan + circuit
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(0.80, 0.95, 1.10)
	var sz := _mascot_box_size()
	var box_w := sz.x
	var box_h := sz.y
	var visor := _mascot_make_image(88, 26, func(img: Image) -> void:
		var frame := Color(0.1, 0.9, 0.95, 0.98)
		var lens := Color(0.05, 0.35, 0.45, 0.7)
		var glow := Color(0.2, 1.0, 1.0, 0.3)
		for y in range(4, 22):
			for x in range(4, 84):
				var on_edge := y <= 5 or y >= 20 or x <= 5 or x >= 83
				if on_edge:
					img.set_pixel(x, y, frame)
				elif y >= 8 and y <= 18:
					img.set_pixel(x, y, lens if (x + y) % 3 != 0 else glow)
		# LED
		for x in [12, 28, 44, 60, 76]:
			img.set_pixel(x, 10, Color(1.0, 0.2, 0.5, 0.95))
	)
	_mascot_add_tex_rect(_mascot_outfit, visor, Vector2(box_w * 0.08, box_h * 0.28), Vector2(box_w * 0.84, box_h * 0.16), 0.0, 2)


func _mascot_outfit_synth() -> void:
	## Lunettes rose / cyan synthwave
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(1.05, 0.90, 1.08)
	var sz := _mascot_box_size()
	var box_w := sz.x
	var box_h := sz.y
	var shades := _mascot_make_image(84, 26, func(img: Image) -> void:
		var frame := Color(0.95, 0.35, 0.85, 0.98)
		var lens_l := Color(0.9, 0.2, 0.6, 0.65)
		var lens_r := Color(0.2, 0.85, 0.9, 0.65)
		for y in range(3, 23):
			for x in range(2, 38):
				var dx := (x - 20) / 16.0
				var dy := (y - 13) / 8.0
				var d2 := dx * dx + dy * dy
				if d2 <= 1.05:
					img.set_pixel(x, y, frame if d2 > 0.78 else lens_l)
			for x in range(46, 82):
				var dx := (x - 64) / 16.0
				var dy := (y - 13) / 8.0
				var d2 := dx * dx + dy * dy
				if d2 <= 1.05:
					img.set_pixel(x, y, frame if d2 > 0.78 else lens_r)
		for y in range(11, 15):
			for x in range(38, 46):
				img.set_pixel(x, y, frame)
	)
	_mascot_add_tex_rect(_mascot_outfit, shades, Vector2(box_w * 0.10, box_h * 0.26), Vector2(box_w * 0.80, box_h * 0.17), 0.0, 2)


func _mascot_outfit_steampunk() -> void:
	## Monocle cuivre + engrenage
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(1.05, 0.95, 0.82)
	var sz := _mascot_box_size()
	var box_w := sz.x
	var box_h := sz.y
	var mono := _mascot_make_image(40, 40, func(img: Image) -> void:
		var brass := Color(0.75, 0.55, 0.22, 0.96)
		var dark := Color(0.35, 0.25, 0.10, 0.95)
		var glass := Color(0.4, 0.55, 0.65, 0.45)
		var cx := 20
		var cy := 20
		for y in range(2, 38):
			for x in range(2, 38):
				var dx := float(x - cx)
				var dy := float(y - cy)
				var d := sqrt(dx * dx + dy * dy)
				if d >= 14.0 and d <= 17.0:
					img.set_pixel(x, y, brass if int(d + x) % 2 == 0 else dark)
				elif d < 14.0:
					img.set_pixel(x, y, glass)
				# Dents engrenage
				if d >= 17.0 and d <= 19.5:
					var ang := atan2(dy, dx)
					if int(ang * 5.0 + 20.0) % 2 == 0:
						img.set_pixel(x, y, brass)
	)
	_mascot_add_tex_rect(_mascot_outfit, mono, Vector2(box_w * 0.48, box_h * 0.22), Vector2(box_w * 0.38, box_h * 0.32), 8.0, 2)


func _mascot_outfit_pixel() -> void:
	## Casque / bordure pixel 8-bit + teinte Game Boy
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(0.75, 1.05, 0.70)
	var sz := _mascot_box_size()
	var box_w := sz.x
	var box_h := sz.y
	var helm := _mascot_make_image(64, 28, func(img: Image) -> void:
		var g1 := Color(0.25, 0.55, 0.20, 0.95)
		var g2 := Color(0.45, 0.75, 0.30, 0.95)
		var blk := Color(0.08, 0.12, 0.06, 0.95)
		for y in range(4, 24):
			for x in range(4, 60):
				var px := x / 4
				var py := y / 4
				if py == 1 or py == 4 or px == 1 or px == 14:
					img.set_pixel(x, y, blk)
				elif py >= 2 and py <= 3 and px >= 2 and px <= 13:
					img.set_pixel(x, y, g1 if (px + py) % 2 == 0 else g2)
		# Visière
		for y in range(12, 18):
			for x in range(16, 48):
				img.set_pixel(x, y, Color(0.15, 0.85, 0.35, 0.7))
	)
	_mascot_add_tex_rect(_mascot_outfit, helm, Vector2(box_w * 0.12, box_h * 0.18), Vector2(box_w * 0.76, box_h * 0.22), 0.0, 2)


func _mascot_outfit_ocean() -> void:
	## Lunettes plongée + teinte cyan
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(0.85, 1.02, 1.12)
	var sz := _mascot_box_size()
	var box_w := sz.x
	var box_h := sz.y
	var goggles := _mascot_make_image(88, 30, func(img: Image) -> void:
		var frame := Color(0.15, 0.45, 0.65, 0.96)
		var lens := Color(0.2, 0.75, 0.9, 0.55)
		var foam := Color(0.85, 0.95, 1.0, 0.4)
		for y in range(4, 26):
			for x in range(4, 40):
				var dx := (x - 22) / 16.0
				var dy := (y - 15) / 10.0
				var d2 := dx * dx + dy * dy
				if d2 <= 1.0:
					img.set_pixel(x, y, frame if d2 > 0.75 else lens)
					if dx < -0.2 and dy < -0.3 and d2 < 0.4:
						img.set_pixel(x, y, foam)
			for x in range(48, 84):
				var dx := (x - 66) / 16.0
				var dy := (y - 15) / 10.0
				var d2 := dx * dx + dy * dy
				if d2 <= 1.0:
					img.set_pixel(x, y, frame if d2 > 0.75 else lens)
					if dx < -0.2 and dy < -0.3 and d2 < 0.4:
						img.set_pixel(x, y, foam)
		for y in range(12, 18):
			for x in range(40, 48):
				img.set_pixel(x, y, frame)
	)
	_mascot_add_tex_rect(_mascot_outfit, goggles, Vector2(box_w * 0.08, box_h * 0.26), Vector2(box_w * 0.84, box_h * 0.18), 0.0, 2)


func _mascot_outfit_manga() -> void:
	## Bandeau + étoiles / traits speed
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(1.05, 0.98, 1.02)
	var sz := _mascot_box_size()
	var box_w := sz.x
	var box_h := sz.y
	var band := _mascot_make_image(90, 18, func(img: Image) -> void:
		var red := Color(0.9, 0.15, 0.18, 0.95)
		var white := Color(0.98, 0.95, 0.92, 0.95)
		for y in range(4, 14):
			for x in range(4, 86):
				img.set_pixel(x, y, red if (x / 8) % 2 == 0 else white)
	)
	_mascot_add_tex_rect(_mascot_outfit, band, Vector2(box_w * 0.05, box_h * 0.12), Vector2(box_w * 0.90, box_h * 0.12), -2.0, 2)


func _mascot_outfit_default() -> void:
	## Identité Thiossane de base : teinte chaude + médaillon or + bandeau subtil
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(1.06, 0.98, 0.88)
	var sz := _mascot_box_size()
	var box_w := sz.x
	var box_h := sz.y
	# Médaillon or (poitrine)
	var medal := _mascot_make_image(40, 44, func(img: Image) -> void:
		var gold := Color(0.92, 0.72, 0.18, 0.95)
		var bright := Color(1.0, 0.88, 0.35, 0.96)
		var dark := Color(0.55, 0.38, 0.08, 0.95)
		var cx := 20
		var cy := 22
		for y in range(4, 40):
			for x in range(4, 36):
				var dx := float(x - cx)
				var dy := float(y - cy)
				var d := sqrt(dx * dx + dy * dy)
				if d < 11.0:
					img.set_pixel(x, y, bright if d < 6.0 else gold)
				elif d < 13.5:
					img.set_pixel(x, y, dark)
		# chaîne simple
		for y in range(0, 8):
			for x in range(16, 24):
				if absf(x - 20) < 2.5 - y * 0.15:
					img.set_pixel(x, y, gold)
	)
	_mascot_add_tex_rect(_mascot_outfit, medal, Vector2(box_w * 0.32, box_h * 0.52), Vector2(box_w * 0.36, box_h * 0.34), 0.0, 2)
	# Mini soleil / étoile dorée près de la couronne
	var spark := _mascot_make_image(24, 24, func(img: Image) -> void:
		var g := Color(0.95, 0.78, 0.22, 0.9)
		var cx := 12
		var cy := 12
		for y in range(1, 23):
			for x in range(1, 23):
				var dx := float(x - cx)
				var dy := float(y - cy)
				var d := sqrt(dx * dx + dy * dy)
				if d < 4.0 or (d < 10.0 and int(atan2(dy, dx) * 3.0 + 12.0) % 2 == 0 and d > 6.0):
					img.set_pixel(x, y, g)
	)
	_mascot_add_tex_rect(_mascot_outfit, spark, Vector2(box_w * 0.68, box_h * 0.04), Vector2(box_w * 0.22, box_h * 0.18), 12.0, 2)


func _mascot_outfit_teranga() -> void:
	## Teranga marquée : soleil, écharpe vert-or-rouge, médaillon
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(1.10, 1.02, 0.86)
	var sz := _mascot_box_size()
	var box_w := sz.x
	var box_h := sz.y
	# Grand soleil doré
	var sun := _mascot_make_image(48, 48, func(img: Image) -> void:
		var gold := Color(0.95, 0.72, 0.15, 0.94)
		var core := Color(1.0, 0.92, 0.40, 0.97)
		var ray := Color(0.98, 0.80, 0.25, 0.88)
		var cx := 24
		var cy := 24
		for y in range(1, 47):
			for x in range(1, 47):
				var dx := float(x - cx)
				var dy := float(y - cy)
				var d := sqrt(dx * dx + dy * dy)
				if d < 9.0:
					img.set_pixel(x, y, core)
				elif d < 13.0:
					img.set_pixel(x, y, gold)
				elif d < 22.0:
					var ang := atan2(dy, dx)
					if int(ang * 5.0 + 20.0) % 2 == 0:
						img.set_pixel(x, y, ray)
	)
	_mascot_add_tex_rect(_mascot_outfit, sun, Vector2(box_w * 0.58, box_h * -0.02), Vector2(box_w * 0.40, box_h * 0.34), 8.0, 2)
	# Écharpe / sash couleurs Sénégal (vert · or · rouge)
	var sash := _mascot_make_image(100, 28, func(img: Image) -> void:
		var green := Color(0.05, 0.52, 0.28, 0.94)
		var gold := Color(0.95, 0.78, 0.12, 0.94)
		var red := Color(0.82, 0.12, 0.14, 0.94)
		var edge := Color(0.15, 0.10, 0.05, 0.55)
		for y in range(2, 26):
			for x in range(2, 98):
				var band := x / 33
				var c := green if band == 0 else (gold if band == 1 else red)
				# motif losange léger
				if ((x / 4) + (y / 3)) % 5 == 0:
					c = Color(minf(c.r + 0.12, 1.0), minf(c.g + 0.10, 1.0), minf(c.b + 0.08, 1.0), c.a)
				img.set_pixel(x, y, c)
			# bords
			for x in range(2, 98):
				img.set_pixel(x, 2, edge)
				img.set_pixel(x, 25, edge)
	)
	_mascot_add_tex_rect(_mascot_outfit, sash, Vector2(box_w * 0.02, box_h * 0.58), Vector2(box_w * 0.96, box_h * 0.22), -6.0, 1)
	# Médaillon central
	var medal := _mascot_make_image(32, 32, func(img: Image) -> void:
		var g := Color(0.95, 0.75, 0.18, 0.96)
		var b := Color(1.0, 0.90, 0.40, 0.97)
		var cx := 16
		var cy := 16
		for y in range(2, 30):
			for x in range(2, 30):
				var d := sqrt(float((x - cx) * (x - cx) + (y - cy) * (y - cy)))
				if d < 9.0:
					img.set_pixel(x, y, b if d < 5.0 else g)
	)
	_mascot_add_tex_rect(_mascot_outfit, medal, Vector2(box_w * 0.36, box_h * 0.62), Vector2(box_w * 0.28, box_h * 0.22), 0.0, 3)


func _mascot_outfit_wax() -> void:
	## Wax bien marqué : bandeau large + pan d’épaule géométrique
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(1.10, 1.00, 0.88)
	var sz := _mascot_box_size()
	var box_w := sz.x
	var box_h := sz.y
	var cols := [
		Color(0.95, 0.55, 0.08, 0.96),  # orange
		Color(0.12, 0.28, 0.72, 0.96),  # indigo
		Color(0.88, 0.15, 0.12, 0.96),  # rouge
		Color(0.20, 0.68, 0.32, 0.96),  # vert
		Color(0.98, 0.88, 0.15, 0.96),  # jaune
	]
	# Bandeau front / couronne — rayures + points
	var band := _mascot_make_image(100, 28, func(img: Image) -> void:
		for y in range(2, 26):
			for x in range(2, 98):
				var i := (x / 7) % cols.size()
				var c: Color = cols[i]
				# points « wax »
				if (x % 6 == 2) and (y % 5 == 2):
					c = Color(1.0, 0.95, 0.55, 0.95)
				elif ((x / 3) + (y / 2)) % 8 == 0:
					c = Color(c.r * 0.7, c.g * 0.7, c.b * 0.7, c.a)
				img.set_pixel(x, y, c)
	)
	_mascot_add_tex_rect(_mascot_outfit, band, Vector2(box_w * 0.02, box_h * 0.06), Vector2(box_w * 0.96, box_h * 0.20), -3.0, 2)
	# Pan d’épaule / cape courte — damier géométrique
	var cape := _mascot_make_image(72, 56, func(img: Image) -> void:
		for y in range(2, 54):
			for x in range(2, 70):
				# forme triangle / drapé
				var edge := 8 + int((y - 2) * 0.55)
				if x < edge or x > 70 - edge / 2:
					continue
				var cx := x / 6
				var cy := y / 6
				var i := (cx + cy) % cols.size()
				var c: Color = cols[i]
				# motif croix / X style print
				if (x % 10 < 2) or (y % 10 < 2):
					c = Color(0.98, 0.92, 0.35, 0.92)
				img.set_pixel(x, y, c)
	)
	_mascot_add_tex_rect(_mascot_outfit, cape, Vector2(box_w * 0.42, box_h * 0.42), Vector2(box_w * 0.56, box_h * 0.48), 8.0, 1)
	# Bracelet / bande poignet stylisé en bas
	var cuff := _mascot_make_image(40, 14, func(img: Image) -> void:
		for y in range(2, 12):
			for x in range(2, 38):
				var i := (x / 5) % cols.size()
				img.set_pixel(x, y, cols[i])
	)
	_mascot_add_tex_rect(_mascot_outfit, cuff, Vector2(box_w * 0.08, box_h * 0.78), Vector2(box_w * 0.32, box_h * 0.12), -12.0, 2)


func _mascot_outfit_sahel() -> void:
	## Turban ocre + voile + teinte sable — plus volumineux
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(1.08, 0.98, 0.86)
	var sz := _mascot_box_size()
	var box_w := sz.x
	var box_h := sz.y
	var turban := _mascot_make_image(104, 48, func(img: Image) -> void:
		var sand := Color(0.90, 0.70, 0.38, 0.96)
		var dark := Color(0.62, 0.40, 0.16, 0.96)
		var cloth := Color(0.94, 0.52, 0.22, 0.96)
		var highlight := Color(0.98, 0.85, 0.55, 0.9)
		for y in range(6, 42):
			for x in range(4, 100):
				var t := absf((x - 52) / 48.0)
				var top := 8.0 + sin(x * 0.12) * 3.5
				if y > top and t < 1.0 - (y - 6) * 0.008:
					var c := sand if (x + y) % 4 != 0 else dark
					if (x / 5 + y / 3) % 6 == 0:
						c = highlight
					img.set_pixel(x, y, c)
		for y in range(2, 18):
			for x in range(16, 88):
				var t := absf((x - 52) / 34.0)
				if t < 0.95:
					img.set_pixel(x, y, cloth if (x / 3) % 2 == 0 else dark)
	)
	_mascot_add_tex_rect(_mascot_outfit, turban, Vector2(box_w * -0.02, box_h * -0.06), Vector2(box_w * 1.04, box_h * 0.40), 0.0, 2)
	# Bande poitrine ocre
	var sash := _mascot_make_image(90, 18, func(img: Image) -> void:
		var a := Color(0.85, 0.55, 0.22, 0.92)
		var b := Color(0.70, 0.40, 0.12, 0.92)
		for y in range(2, 16):
			for x in range(2, 88):
				img.set_pixel(x, y, a if (x / 6) % 2 == 0 else b)
	)
	_mascot_add_tex_rect(_mascot_outfit, sash, Vector2(box_w * 0.06, box_h * 0.62), Vector2(box_w * 0.88, box_h * 0.14), -4.0, 1)


func _mascot_outfit_savane() -> void:
	## Feuille baobab + soleil + herbes — plus présent
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(0.96, 1.06, 0.88)
	var sz := _mascot_box_size()
	var box_w := sz.x
	var box_h := sz.y
	# Soleil
	var sun := _mascot_make_image(32, 32, func(img: Image) -> void:
		var gold := Color(0.98, 0.80, 0.20, 0.92)
		var cx := 16
		var cy := 16
		for y in range(1, 31):
			for x in range(1, 31):
				var d := sqrt(float((x - cx) * (x - cx) + (y - cy) * (y - cy)))
				if d < 7.0 or (d < 14.0 and int(atan2(float(y - cy), float(x - cx)) * 4.0 + 12.0) % 2 == 0):
					img.set_pixel(x, y, gold)
	)
	_mascot_add_tex_rect(_mascot_outfit, sun, Vector2(box_w * 0.68, box_h * 0.00), Vector2(box_w * 0.28, box_h * 0.24), 0.0, 2)
	# Grande feuille
	var leaf := _mascot_make_image(56, 56, func(img: Image) -> void:
		var green := Color(0.32, 0.72, 0.22, 0.94)
		var dark := Color(0.18, 0.48, 0.10, 0.94)
		var gold := Color(0.95, 0.78, 0.22, 0.92)
		for y in range(4, 52):
			for x in range(6, 50):
				var dx := (x - 28) / 16.0
				var dy := (y - 28) / 22.0
				var d2 := dx * dx + dy * dy
				if d2 <= 1.0:
					img.set_pixel(x, y, green if (x + y) % 3 != 0 else dark)
		for y in range(8, 48):
			img.set_pixel(28, y, gold)
			if y % 4 == 0:
				for ox in range(1, 6):
					if 28 + ox < 56:
						img.set_pixel(28 + ox, y, gold)
	)
	_mascot_add_tex_rect(_mascot_outfit, leaf, Vector2(box_w * 0.52, box_h * 0.08), Vector2(box_w * 0.44, box_h * 0.38), 18.0, 2)
	# Touffe d’herbe bas
	var grass := _mascot_make_image(80, 20, func(img: Image) -> void:
		var g1 := Color(0.40, 0.75, 0.25, 0.9)
		var g2 := Color(0.25, 0.55, 0.15, 0.9)
		for x in range(2, 78):
			var h := 6 + int(absf(sin(x * 0.4)) * 10.0)
			for y in range(18 - h, 18):
				img.set_pixel(x, y, g1 if (x + y) % 2 == 0 else g2)
	)
	_mascot_add_tex_rect(_mascot_outfit, grass, Vector2(box_w * 0.10, box_h * 0.82), Vector2(box_w * 0.80, box_h * 0.16), 0.0, 1)


func _mascot_outfit_gangster() -> void:
	## Chapeau fedora + lunettes noires 90s
	if is_instance_valid(_mascot_tex):
		_mascot_tex.modulate = Color(0.95, 0.95, 0.98)
	var sz := _mascot_box_size()
	var box_w := sz.x
	var box_h := sz.y
	var hat := _mascot_make_image(96, 36, func(img: Image) -> void:
		var black := Color(0.12, 0.12, 0.14, 0.96)
		var grey := Color(0.28, 0.28, 0.30, 0.95)
		for y in range(18, 32):
			for x in range(2, 94):
				var t := absf((x - 48) / 46.0)
				if t < 1.0 - (y - 18) * 0.02:
					img.set_pixel(x, y, black)
		for y in range(4, 22):
			for x in range(24, 72):
				var t := absf((x - 48) / 24.0)
				if t < 1.0 - (y - 4) * 0.015:
					img.set_pixel(x, y, black if (x + y) % 4 != 0 else grey)
	)
	_mascot_add_tex_rect(_mascot_outfit, hat, Vector2(box_w * 0.02, box_h * -0.04), Vector2(box_w * 0.96, box_h * 0.30), 0.0, 2)
	var shades := _mascot_make_image(80, 24, func(img: Image) -> void:
		var frame := Color(0.08, 0.08, 0.10, 0.98)
		var lens := Color(0.15, 0.15, 0.18, 0.85)
		for y in range(3, 21):
			for x in range(2, 36):
				var dx := (x - 19) / 15.0
				var dy := (y - 12) / 8.0
				var d2 := dx * dx + dy * dy
				if d2 <= 1.0:
					img.set_pixel(x, y, frame if d2 > 0.75 else lens)
			for x in range(44, 78):
				var dx := (x - 61) / 15.0
				var dy := (y - 12) / 8.0
				var d2 := dx * dx + dy * dy
				if d2 <= 1.0:
					img.set_pixel(x, y, frame if d2 > 0.75 else lens)
		for y in range(10, 14):
			for x in range(36, 44):
				img.set_pixel(x, y, frame)
	)
	_mascot_add_tex_rect(_mascot_outfit, shades, Vector2(box_w * 0.12, box_h * 0.28), Vector2(box_w * 0.76, box_h * 0.15), 0.0, 2)


# ══════════════════════════════════════════════════════════════════════════════
# MODE FESTIF — fin d'année (neige + guirlandes), Korité, Tabaski, fêtes locales
# ══════════════════════════════════════════════════════════════════════════════

func _festive_detect() -> String:
	## Ambiance festive 100 % automatique selon la date du système.
	if not _festive_enabled:
		return ""
	var d := Time.get_date_dict_from_system()
	var y := int(d.get("year", 2026))
	var m := int(d.get("month", 1))
	var day := int(d.get("day", 1))
	var ordinal := m * 100 + day  # ex: 1225 = 25 déc

	# Fin d'année / Noël / Nouvel An : 1er déc → 6 jan
	if ordinal >= 1201 or ordinal <= 106:
		return "winter"

	# Fête de l'Indépendance du Sénégal — 4 avril
	if m == 4 and day >= 3 and day <= 5:
		return "independence"

	# Korité (Aïd el-Fitr) — dates approx. (±2 j) pour quelques années
	# Source indicative ; le calendrier lunaire peut varier d’un jour.
	var korite_dates := {
		2024: [4, 10],   # ~10 avril 2024
		2025: [3, 30],   # ~30 mars 2025
		2026: [3, 20],   # ~20 mars 2026
		2027: [3, 10],   # ~9-10 mars 2027
		2028: [2, 27],   # ~26-27 fév 2028
	}
	if korite_dates.has(y):
		var km: int = korite_dates[y][0]
		var kd: int = korite_dates[y][1]
		if m == km and absi(day - kd) <= 2:
			return "korite"
		# fenêtre élargie veille / lendemain de mois adjacent
		if absi(_festive_day_diff(y, m, day, y, km, kd)) <= 2:
			return "korite"

	# Tabaski (Aïd el-Kebir) — dates approx. (±2 j)
	var tabaski_dates := {
		2024: [6, 16],
		2025: [6, 6],
		2026: [5, 27],
		2027: [5, 17],
		2028: [5, 5],
	}
	if tabaski_dates.has(y):
		var tm: int = tabaski_dates[y][0]
		var td: int = tabaski_dates[y][1]
		if absi(_festive_day_diff(y, m, day, y, tm, td)) <= 2:
			return "tabaski"

	return ""


func _festive_day_diff(y1: int, m1: int, d1: int, y2: int, m2: int, d2: int) -> int:
	var t1 := Time.get_unix_time_from_datetime_dict({"year": y1, "month": m1, "day": d1, "hour": 12, "minute": 0, "second": 0})
	var t2 := Time.get_unix_time_from_datetime_dict({"year": y2, "month": m2, "day": d2, "hour": 12, "minute": 0, "second": 0})
	return int(round((t1 - t2) / 86400.0))


func _festive_apply() -> void:
	_festive_id = _festive_detect()
	_festive_clear_fx()
	if _festive_id == "":
		if is_instance_valid(_festive_banner):
			_festive_banner.visible = false
		if is_instance_valid(_garland_bar):
			_garland_bar.visible = false
		return
	_festive_build_banner()
	_festive_build_garland()
	if _festive_id == "winter":
		_festive_start_snow()
	_festive_tint_banner()
	_log(tr_ui("festive_active") % tr_ui("festive_name_" + _festive_id), "ok")


func _festive_clear_fx() -> void:
	if is_instance_valid(_snow_particles):
		_snow_particles.queue_free()
		_snow_particles = null
	if is_instance_valid(_festive_layer):
		_festive_layer.queue_free()
		_festive_layer = null
	if is_instance_valid(_garland_bar):
		for c in _garland_bar.get_children():
			c.queue_free()


func _festive_build_banner() -> void:
	if not is_instance_valid(_festive_banner):
		return
	_festive_banner.visible = true
	_festive_banner.text = tr_ui("festive_banner_" + _festive_id)
	match _festive_id:
		"winter":
			_festive_banner.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
		"korite":
			_festive_banner.add_theme_color_override("font_color", Color(0.45, 0.85, 0.55))
		"tabaski":
			_festive_banner.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
		"independence":
			_festive_banner.add_theme_color_override("font_color", Color(0.35, 0.75, 0.45))
		_:
			_festive_banner.add_theme_color_override("font_color", C_PRIMARY)


func _festive_build_garland() -> void:
	if not is_instance_valid(_garland_bar):
		return
	_garland_bar.visible = true
	for c in _garland_bar.get_children():
		c.queue_free()
	var colors: Array = []
	match _festive_id:
		"winter":
			colors = [
				Color(0.85, 0.15, 0.15), Color(0.2, 0.65, 0.25), Color(0.95, 0.85, 0.2),
				Color(0.85, 0.15, 0.15), Color(0.2, 0.65, 0.25), Color(0.95, 0.85, 0.2),
				Color(0.9, 0.9, 1.0), Color(0.85, 0.15, 0.15), Color(0.2, 0.65, 0.25),
			]
		"korite":
			colors = [
				Color(0.15, 0.55, 0.30), Color(0.95, 0.85, 0.35), Color(0.95, 0.95, 0.95),
				Color(0.15, 0.55, 0.30), Color(0.95, 0.85, 0.35), Color(0.95, 0.95, 0.95),
				Color(0.15, 0.55, 0.30), Color(0.95, 0.85, 0.35),
			]
		"tabaski":
			colors = [
				Color(0.95, 0.80, 0.20), Color(0.20, 0.55, 0.30), Color(0.95, 0.95, 0.92),
				Color(0.95, 0.80, 0.20), Color(0.20, 0.55, 0.30), Color(0.95, 0.95, 0.92),
				Color(0.95, 0.80, 0.20),
			]
		"independence":
			# Vert / or / rouge inspiré drapeau sénégalais
			colors = [
				Color(0.05, 0.55, 0.25), Color(0.95, 0.80, 0.15), Color(0.85, 0.12, 0.15),
				Color(0.05, 0.55, 0.25), Color(0.95, 0.80, 0.15), Color(0.85, 0.12, 0.15),
				Color(0.05, 0.55, 0.25), Color(0.95, 0.80, 0.15),
			]
		_:
			colors = [C_PRIMARY]
	for i in range(colors.size()):
		var bulb := Panel.new()
		bulb.custom_minimum_size = Vector2(10, 10)
		var sb := StyleBoxFlat.new()
		sb.bg_color = colors[i]
		sb.set_corner_radius_all(5)
		sb.shadow_color = Color(colors[i].r, colors[i].g, colors[i].b, 0.45)
		sb.shadow_size = 3
		bulb.add_theme_stylebox_override("panel", sb)
		_garland_bar.add_child(bulb)
		# Fil de guirlande entre les ampoules
		if i < colors.size() - 1:
			var wire := ColorRect.new()
			wire.custom_minimum_size = Vector2(8, 2)
			wire.color = Color(0.35, 0.32, 0.28)
			wire.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_garland_bar.add_child(wire)


func _festive_tint_banner() -> void:
	if not is_instance_valid(_status_banner):
		return
	var sb := _status_banner.get_theme_stylebox("panel")
	if not (sb is StyleBoxFlat):
		return
	var s: StyleBoxFlat = (sb as StyleBoxFlat).duplicate()
	match _festive_id:
		"winter":
			s.border_color = Color(0.55, 0.75, 0.95, 0.8)
		"korite":
			s.border_color = Color(0.25, 0.7, 0.4, 0.85)
		"tabaski":
			s.border_color = Color(0.9, 0.75, 0.25, 0.85)
		"independence":
			s.border_color = Color(0.15, 0.65, 0.3, 0.85)
	_status_banner.add_theme_stylebox_override("panel", s)


func _festive_start_snow() -> void:
	## Neige légère par-dessus le dock (ne bloque pas les clics).
	if is_instance_valid(_festive_layer):
		_festive_layer.queue_free()
	_festive_layer = Control.new()
	_festive_layer.name = "FestiveSnow"
	_festive_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_festive_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_festive_layer.z_index = 80
	add_child(_festive_layer)

	_snow_particles = CPUParticles2D.new()
	_snow_particles.name = "Snow"
	_snow_particles.amount = 48
	_snow_particles.lifetime = 6.5
	_snow_particles.preprocess = 3.0
	_snow_particles.explosiveness = 0.0
	_snow_particles.randomness = 0.7
	_snow_particles.local_coords = false
	_snow_particles.emitting = true
	_snow_particles.direction = Vector2(0.15, 1.0)
	_snow_particles.spread = 25.0
	_snow_particles.gravity = Vector2(0, 28)
	_snow_particles.initial_velocity_min = 12.0
	_snow_particles.initial_velocity_max = 36.0
	_snow_particles.scale_amount_min = 1.5
	_snow_particles.scale_amount_max = 3.5
	_snow_particles.color = Color(0.92, 0.95, 1.0, 0.75)
	# Zone d'émission : haut du panneau
	_snow_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_snow_particles.emission_rect_extents = Vector2(200, 8)
	_snow_particles.position = Vector2(160, -10)
	_snow_particles.z_index = 80
	_festive_layer.add_child(_snow_particles)

	# Ajuster la largeur d'émission au redimensionnement
	_festive_sync_snow_size()
	var snow_cb := Callable(self, "_festive_sync_snow_size")
	if not resized.is_connected(snow_cb):
		resized.connect(snow_cb)


func _festive_sync_snow_size() -> void:
	if not is_instance_valid(_snow_particles):
		return
	var w := maxf(size.x, 280.0)
	_snow_particles.emission_rect_extents = Vector2(w * 0.55, 10.0)
	_snow_particles.position = Vector2(w * 0.5, -12.0)
	_snow_particles.amount = clampi(int(w / 8.0), 28, 70)





# ══════════════════════════════════════════════════════════════════════════════
# MODE NUIT FOCUS — après 22 h : plus sombre, tips calmes, playlist suggérée
# ══════════════════════════════════════════════════════════════════════════════

func _night_focus_active_now() -> bool:
	var h := int(Time.get_time_dict_from_system().get("hour", 12))
	return h >= 22 or h < 6


func _night_focus_apply() -> void:
	var want := _night_focus_active_now()
	if want == _night_focus and is_instance_valid(_night_overlay):
		return
	_night_focus = want
	if not want:
		if is_instance_valid(_night_overlay):
			_night_overlay.queue_free()
			_night_overlay = null
		if is_instance_valid(_root_vbox):
			_root_vbox.modulate = Color.WHITE
		return
	# Voile sombre très léger (ne bloque pas les clics)
	if not is_instance_valid(_night_overlay):
		_night_overlay = ColorRect.new()
		_night_overlay.name = "NightFocusVeil"
		_night_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_night_overlay.color = Color(0.05, 0.07, 0.12, 0.12)
		_night_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_night_overlay.z_index = 5
		add_child(_night_overlay)
	if is_instance_valid(_root_vbox):
		_root_vbox.modulate = Color(0.92, 0.93, 0.98)
	# Tip calme
	if is_instance_valid(_tip_label) and not is_busy:
		_tip_label.text = "🌙 " + tr_ui("night_tip")
	# Suggérer la musique si playlist dispo et rien en lecture
	if not _night_music_hinted and _music_playlist.size() > 0 and is_instance_valid(_music_player):
		if not _music_player.playing:
			_feedback(tr_ui("night_music_hint"), "info")
			_night_music_hinted = true
	_comfort_refresh_greeting()



# ══════════════════════════════════════════════════════════════════════════════
# CONFORT UX — envie d'y rester (accueil, tips, mode cosy, encouragements)
# ══════════════════════════════════════════════════════════════════════════════

func _comfort_hour_bucket() -> String:
	var h := Time.get_time_dict_from_system().get("hour", 12)
	if h < 6:
		return "night"
	if h < 12:
		return "morning"
	if h < 18:
		return "afternoon"
	return "evening"


func _comfort_refresh_greeting() -> void:
	if not is_instance_valid(_greet_label):
		return
	var bucket := _comfort_hour_bucket()
	var key := "greet_" + bucket
	if access_token != "" and current_user is Dictionary and current_user.has("email"):
		var mail := str(current_user.get("email", ""))
		var name := mail.split("@")[0] if "@" in mail else mail
		if name != "":
			_greet_label.text = tr_ui("greet_named") % [tr_ui(key), name]
		else:
			_greet_label.text = tr_ui(key)
	else:
		_greet_label.text = tr_ui(key)
	# Session douce
	if _session_start_sec > 0.0:
		var mins := int((Time.get_unix_time_from_system() - _session_start_sec) / 60.0)
		if mins >= 25 and not is_busy:
			_greet_label.text += "  ·  " + (tr_ui("comfort_stretch") if mins < 50 else tr_ui("comfort_long_session") % mins)


func _on_comfort_tip_tick() -> void:
	if is_busy:
		return
	if not is_instance_valid(_tip_label):
		return
	if _night_focus:
		var night_tips := ["night_tip", "night_tip_2", "night_tip_3"]
		_tip_index = (_tip_index + 1) % night_tips.size()
		_tip_label.text = "🌙 " + tr_ui(night_tips[_tip_index])
		return
	var tips := [
		"tip_1", "tip_2", "tip_3", "tip_4", "tip_5",
		"tip_6", "tip_7", "tip_8", "tip_9", "tip_10",
	]
	_tip_index = (_tip_index + 1) % tips.size()
	_tip_label.text = "💡 " + tr_ui(tips[_tip_index])


func _on_busy_tip_tick() -> void:
	if not is_busy or not is_instance_valid(_tip_label):
		return
	# Après quelques ticks, proposer discrètement un Chaos (une seule fois par session busy)
	if not _chaos_hint_shown_this_busy and _tip_index >= 2 and not _chaos_active:
		_chaos_hint_shown_this_busy = true
		_tip_label.text = "💥 " + tr_ui("busy_tip_chaos")
		return
	var tips := ["busy_tip_1", "busy_tip_2", "busy_tip_3", "busy_tip_4", "busy_tip_5"]
	_tip_index = (_tip_index + 1) % tips.size()
	_tip_label.text = "… " + tr_ui(tips[_tip_index])


func _on_cozy_toggled(on: bool) -> void:
	_cozy_mode = on
	_apply_cozy_mode(true)
	_save_config()
	if is_instance_valid(_cozy_btn):
		_cozy_btn.text = tr_ui("cozy_on") if on else tr_ui("cozy_btn")


func _apply_cozy_mode(animate: bool = false) -> void:
	## Mode cosy : plus d’air, typo un peu plus grande, ambiance plus douce.
	if is_instance_valid(_root_vbox):
		_root_vbox.add_theme_constant_override("separation", 12 if _cozy_mode else 6)
	if is_instance_valid(_greet_label):
		_greet_label.add_theme_font_size_override("font_size", _ed_font(0 if _cozy_mode else -1))
		_greet_label.modulate = Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.85) if _cozy_mode else C_MUTED
	if is_instance_valid(_tip_label):
		_tip_label.visible = true
		_tip_label.modulate = Color(C_PRIMARY.r, C_PRIMARY.g, C_PRIMARY.b, 0.75) if _cozy_mode else C_MUTED
	if is_instance_valid(_status_banner):
		var sb := _status_banner.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			var s: StyleBoxFlat = (sb as StyleBoxFlat).duplicate()
			s.set_corner_radius_all(14 if _cozy_mode else 10)
			s.content_margin_top = 12 if _cozy_mode else 10
			s.content_margin_bottom = 12 if _cozy_mode else 10
			_status_banner.add_theme_stylebox_override("panel", s)
	if animate and is_instance_valid(_status_banner):
		_status_banner.modulate = Color(1, 1, 1, 0.7)
		var tw := create_tween()
		tw.tween_property(_status_banner, "modulate:a", 1.0, 0.25)
	_comfort_refresh_greeting()


func _comfort_on_success() -> void:
	## Petit boost après une action réussie (deploy, login, fiche…).
	if is_instance_valid(_tip_label):
		_tip_label.text = "✔ " + tr_ui("comfort_success")
	_comfort_refresh_greeting()



# ══════════════════════════════════════════════════════════════════════════════
# PAUSE BIEN-ÊTRE — animations 3D (café, cola, pizza, clope, marijuana)
# Cigarette / marijuana : messages santé + rappel légal (marijuana illégale selon pays)
# ══════════════════════════════════════════════════════════════════════════════


# ══════════════════════════════════════════════════════════════════════════════
# CHAOS FX — exploser / brûler / geler l’interface (+ fumée)
# ══════════════════════════════════════════════════════════════════════════════


func _on_chaos_opt_intensity(idx: int) -> void:
	if is_instance_valid(_chaos_opt_intensity):
		_chaos_intensity = float(_chaos_opt_intensity.get_item_metadata(idx))
		_save_config()


func _on_chaos_opt_duration(idx: int) -> void:
	if is_instance_valid(_chaos_opt_duration):
		_chaos_duration_mult = float(_chaos_opt_duration.get_item_metadata(idx))
		_save_config()


func _on_chaos_opt_particles(on: bool) -> void:
	_chaos_particles = on
	_save_config()


func _on_chaos_opt_auto(on: bool) -> void:
	_chaos_auto_restore = on
	_save_config()


func _on_chaos_opt_shake(on: bool) -> void:
	_chaos_shake = on
	_save_config()


func _on_chaos_opt_emojis(on: bool) -> void:
	_chaos_emojis = on
	_save_config()


func _on_chaos_opt_on_success(on: bool) -> void:
	_chaos_on_success = on
	_save_config()


func _on_chaos_pressed() -> void:
	if _chaos_active:
		_chaos_restore()
		return
	_show_chaos_menu()


func _show_chaos_menu() -> void:
	if is_instance_valid(_chaos_layer):
		_chaos_layer.queue_free()
		_chaos_layer = null

	_chaos_layer = Control.new()
	_chaos_layer.name = "ChaosMenuLayer"
	_chaos_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_chaos_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_chaos_layer.z_index = 260
	add_child(_chaos_layer)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.02, 0.08, 0.85)
	_chaos_layer.add_child(dim)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 14)
	_chaos_layer.add_child(center)

	var title := Label.new()
	title.text = tr_ui("chaos_menu_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", _ed_font(6))
	title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.2))
	center.add_child(title)

	var boom_hint := Label.new()
	boom_hint.text = "💥 · 🔥 · ❄️ · 🚨 · 🟢 MATRIX · 🤖 T-800"
	boom_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boom_hint.add_theme_font_size_override("font_size", _ed_font(3))
	center.add_child(boom_hint)

	var sub := Label.new()
	sub.text = tr_ui("chaos_menu_sub")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", _ed_font(-1))
	sub.modulate = C_MUTED
	center.add_child(sub)

	# ── Options de personnalisation ────────────────────────────────────────
	var opts_title := Label.new()
	opts_title.text = tr_ui("chaos_opts_title")
	opts_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opts_title.add_theme_font_size_override("font_size", _ed_font())
	opts_title.add_theme_color_override("font_color", C_PRIMARY)
	center.add_child(opts_title)

	var opts := VBoxContainer.new()
	opts.add_theme_constant_override("separation", 6)
	opts.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(opts)

	var row_int := HBoxContainer.new()
	row_int.add_theme_constant_override("separation", 8)
	opts.add_child(row_int)
	var lbl_int := Label.new()
	lbl_int.text = tr_ui("chaos_opt_intensity")
	lbl_int.custom_minimum_size.x = 110
	row_int.add_child(lbl_int)
	_chaos_opt_intensity = OptionButton.new()
	_chaos_opt_intensity.add_item(tr_ui("chaos_int_low"), 0)
	_chaos_opt_intensity.set_item_metadata(0, 0.6)
	_chaos_opt_intensity.add_item(tr_ui("chaos_int_med"), 1)
	_chaos_opt_intensity.set_item_metadata(1, 1.0)
	_chaos_opt_intensity.add_item(tr_ui("chaos_int_high"), 2)
	_chaos_opt_intensity.set_item_metadata(2, 1.5)
	_chaos_opt_intensity.add_item(tr_ui("chaos_int_insane"), 3)
	_chaos_opt_intensity.set_item_metadata(3, 2.2)
	# select current
	for i in _chaos_opt_intensity.item_count:
		if is_equal_approx(float(_chaos_opt_intensity.get_item_metadata(i)), _chaos_intensity):
			_chaos_opt_intensity.select(i)
			break
	_chaos_opt_intensity.item_selected.connect(_on_chaos_opt_intensity)
	row_int.add_child(_chaos_opt_intensity)
	_style_option_button(_chaos_opt_intensity)

	var row_dur := HBoxContainer.new()
	row_dur.add_theme_constant_override("separation", 8)
	opts.add_child(row_dur)
	var lbl_dur := Label.new()
	lbl_dur.text = tr_ui("chaos_opt_duration")
	lbl_dur.custom_minimum_size.x = 110
	row_dur.add_child(lbl_dur)
	_chaos_opt_duration = OptionButton.new()
	_chaos_opt_duration.add_item(tr_ui("chaos_dur_short"), 0)
	_chaos_opt_duration.set_item_metadata(0, 0.7)
	_chaos_opt_duration.add_item(tr_ui("chaos_dur_med"), 1)
	_chaos_opt_duration.set_item_metadata(1, 1.0)
	_chaos_opt_duration.add_item(tr_ui("chaos_dur_long"), 2)
	_chaos_opt_duration.set_item_metadata(2, 1.5)
	for i in _chaos_opt_duration.item_count:
		if is_equal_approx(float(_chaos_opt_duration.get_item_metadata(i)), _chaos_duration_mult):
			_chaos_opt_duration.select(i)
			break
	_chaos_opt_duration.item_selected.connect(_on_chaos_opt_duration)
	row_dur.add_child(_chaos_opt_duration)
	_style_option_button(_chaos_opt_duration)

	var row_chk := HFlowContainer.new()
	row_chk.add_theme_constant_override("h_separation", 10)
	opts.add_child(row_chk)
	_chaos_chk_particles = CheckBox.new()
	_chaos_chk_particles.text = tr_ui("chaos_opt_particles")
	_chaos_chk_particles.button_pressed = _chaos_particles
	_chaos_chk_particles.toggled.connect(_on_chaos_opt_particles)
	row_chk.add_child(_chaos_chk_particles)
	_style_checkbox(_chaos_chk_particles)
	_chaos_chk_auto = CheckBox.new()
	_chaos_chk_auto.text = tr_ui("chaos_opt_auto")
	_chaos_chk_auto.button_pressed = _chaos_auto_restore
	_chaos_chk_auto.toggled.connect(_on_chaos_opt_auto)
	row_chk.add_child(_chaos_chk_auto)
	_style_checkbox(_chaos_chk_auto)
	_chaos_chk_shake = CheckBox.new()
	_chaos_chk_shake.text = tr_ui("chaos_opt_shake")
	_chaos_chk_shake.button_pressed = _chaos_shake
	_chaos_chk_shake.toggled.connect(_on_chaos_opt_shake)
	row_chk.add_child(_chaos_chk_shake)
	_style_checkbox(_chaos_chk_shake)
	_chaos_chk_emojis = CheckBox.new()
	_chaos_chk_emojis.text = tr_ui("chaos_opt_emojis")
	_chaos_chk_emojis.button_pressed = _chaos_emojis
	_chaos_chk_emojis.toggled.connect(_on_chaos_opt_emojis)
	row_chk.add_child(_chaos_chk_emojis)
	_style_checkbox(_chaos_chk_emojis)
	_chaos_chk_on_success = CheckBox.new()
	_chaos_chk_on_success.text = tr_ui("chaos_opt_on_success")
	_chaos_chk_on_success.button_pressed = _chaos_on_success
	_chaos_chk_on_success.toggled.connect(_on_chaos_opt_on_success)
	_chaos_chk_on_success.tooltip_text = tr_ui("chaos_opt_on_success_tip")
	row_chk.add_child(_chaos_chk_on_success)
	_style_checkbox(_chaos_chk_on_success)

	var grid := HFlowContainer.new()
	grid.alignment = 1
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	center.add_child(grid)

	var kinds := [
		["explode", "chaos_explode", Color(1.0, 0.5, 0.15)],
		["burn", "chaos_burn", Color(1.0, 0.28, 0.08)],
		["freeze", "chaos_freeze", Color(0.4, 0.75, 1.0)],
		["pressure", "chaos_pressure", Color(1.0, 0.15, 0.2)],
		["matrix", "chaos_matrix", Color(0.2, 0.95, 0.35)],
		["terminator", "chaos_terminator", Color(0.95, 0.15, 0.12)],
	]
	for pair in kinds:
		var kind: String = pair[0]
		var key: String = pair[1]
		var col: Color = pair[2]
		var b := Button.new()
		b.text = tr_ui(key)
		b.custom_minimum_size = Vector2(150, 44)
		b.pressed.connect(_on_chaos_kind_chosen.bind(kind))
		grid.add_child(b)
		_style_secondary_button(b)
		b.add_theme_color_override("font_color", col)
		b.add_theme_color_override("font_hover_color", col.lightened(0.25))

	var cancel := Button.new()
	cancel.text = tr_ui("chaos_cancel")
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_chaos_close_menu)
	center.add_child(cancel)
	_style_primary_button(cancel)

	_chaos_layer.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(_chaos_layer, "modulate:a", 1.0, 0.18)


func _chaos_close_menu() -> void:
	if is_instance_valid(_chaos_layer):
		_chaos_layer.queue_free()
		_chaos_layer = null


func _on_chaos_kind_chosen(kind: String) -> void:
	_chaos_close_menu()
	_chaos_kind = kind
	_chaos_start(kind)


func _chaos_collect_targets() -> Array:
	var out: Array = []
	var roots: Array = []
	for c in get_children():
		if c is Control and str(c.name) not in ["ChaosMenuLayer", "ChaosFxLayer", "BreakMenuLayer"] \
				and not str(c.name).begins_with("Coffee") and not str(c.name).begins_with("Break"):
			roots.append(c)
	var stack: Array = roots.duplicate()
	while not stack.is_empty():
		var n = stack.pop_back()
		if not is_instance_valid(n) or not (n is CanvasItem):
			continue
		if n is Button or n is Label or n is LineEdit or n is TextEdit or n is OptionButton \
				or n is CheckBox or n is ProgressBar or n is SpinBox or n is PanelContainer \
				or n is ItemList or n is HSlider:
			out.append(n)
		if n is Control and n.get_child_count() > 0 and out.size() < 100:
			for ch in n.get_children():
				stack.append(ch)
		if out.size() >= 100:
			break
	return out


func _chaos_save_state(nodes: Array) -> void:
	_chaos_saved.clear()
	for n in nodes:
		if not is_instance_valid(n) or not (n is CanvasItem):
			continue
		var ci := n as CanvasItem
		_chaos_saved.append({
			"node": ci,
			"modulate": ci.modulate,
			"position": n.position if n is Control else Vector2.ZERO,
			"rotation": n.rotation if n is Control else 0.0,
			"scale": n.scale if n is Control else Vector2.ONE,
		})


func _chaos_make_tween() -> Tween:
	## Tween tracké : tué automatiquement dans _chaos_restore (corrige UI noire après burn).
	var tw := create_tween()
	_chaos_tweens.append(tw)
	return tw


func _chaos_kill_tweens() -> void:
	for tw in _chaos_tweens:
		if tw is Tween and is_instance_valid(tw):
			tw.kill()
	_chaos_tweens.clear()


func _chaos_start(kind: String) -> void:
	if _chaos_active:
		_chaos_restore()
	_chaos_kill_tweens()
	_chaos_active = true
	_chaos_kind = kind
	var targets := _chaos_collect_targets()
	_chaos_save_state(targets)

	if is_instance_valid(_chaos_layer):
		_chaos_layer.queue_free()
	_chaos_layer = Control.new()
	_chaos_layer.name = "ChaosFxLayer"
	_chaos_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_chaos_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chaos_layer.z_index = 240
	add_child(_chaos_layer)

	# Punch global du dock
	if _chaos_shake:
		_chaos_screen_punch()

	match kind:
		"explode":
			_chaos_fx_explode(targets)
		"burn":
			_chaos_fx_burn(targets)
		"freeze":
			_chaos_fx_freeze(targets)
		"pressure":
			_chaos_fx_pressure(targets)
		"matrix":
			_chaos_fx_matrix(targets)
		"terminator":
			_chaos_fx_terminator(targets)

	_log(tr_ui("chaos_log_%s" % kind), "warn")
	_feedback(tr_ui("chaos_fb_%s" % kind), "warn")
	if is_instance_valid(_chaos_btn):
		_chaos_btn.text = tr_ui("chaos_restore")

	var base_delay := 5.5 if kind == "explode" else (7.5 if kind in ["pressure", "matrix", "terminator"] else 6.5)
	var delay := base_delay * clampf(_chaos_duration_mult, 0.5, 2.0)
	if _chaos_auto_restore:
		var t := get_tree().create_timer(delay)
		t.timeout.connect(func() -> void:
			if _chaos_active and _chaos_kind == kind:
				_chaos_restore()
		)


func _chaos_screen_punch() -> void:
	## Le dock entier secoue + scale punch « BOOM ».
	var base_pos := position
	var tw := _chaos_make_tween()
	tw.set_parallel(true)
	var k := clampf(_chaos_intensity, 0.5, 2.5)
	tw.tween_property(self, "scale", Vector2(1.0 + 0.06 * k, 1.0 + 0.06 * k), 0.08).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_property(self, "scale", Vector2(0.97, 0.97), 0.1)
	tw.chain().tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC)
	# Shake
	var shake := _chaos_make_tween()
	var n_shake := clampi(int(8 * k), 4, 16)
	for i in n_shake:
		var off := Vector2(randf_range(-10, 10) * k, randf_range(-8, 8) * k)
		shake.tween_property(self, "position", base_pos + off, 0.04)
	shake.tween_property(self, "position", base_pos, 0.08)


func _chaos_soft_tex(radius: int = 16) -> ImageTexture:
	var s := radius * 2
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(radius, radius)
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / float(radius)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _chaos_spawn_smoke(color: Color, amount: int = 48, upward: bool = true) -> CPUParticles2D:
	if not _chaos_particles:
		return null
	var p := CPUParticles2D.new()
	p.z_index = 5
	p.amount = clampi(int(amount * _chaos_intensity), 8, 160)
	p.lifetime = 2.4
	p.preprocess = 0.35
	p.explosiveness = 0.25
	p.randomness = 0.7
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(maxi(size.x * 0.48, 80), maxi(size.y * 0.4, 60))
	p.position = size * 0.5
	p.direction = Vector2(0, -1) if upward else Vector2(0, 1)
	p.spread = 48.0
	p.gravity = Vector2(0, -22 if upward else 45)
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 95.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 9.0
	p.color = color
	p.texture = _chaos_soft_tex(14)
	_chaos_layer.add_child(p)
	p.emitting = true
	_chaos_smoke = p
	return p


func _chaos_spawn_embers(color: Color, amount: int = 40) -> CPUParticles2D:
	if not _chaos_particles:
		return null
	var p := CPUParticles2D.new()
	p.z_index = 6
	p.amount = clampi(int(amount * _chaos_intensity), 6, 120)
	p.lifetime = 1.6
	p.explosiveness = 0.55
	p.randomness = 0.8
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(maxi(size.x * 0.42, 60), maxi(size.y * 0.42, 60))
	p.position = size * 0.5
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.gravity = Vector2(0, -40)
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 160.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.color = color
	p.texture = _chaos_soft_tex(6)
	_chaos_layer.add_child(p)
	p.emitting = true
	_chaos_embers = p
	return p


func _chaos_spawn_confetti() -> void:
	## Petits carrés colorés qui partent dans tous les sens.
	if not _chaos_particles:
		return
	var colors := [
		Color(1, 0.3, 0.2), Color(1, 0.85, 0.2), Color(0.3, 0.9, 0.4),
		Color(0.3, 0.6, 1.0), Color(0.9, 0.4, 1.0), Color(1, 0.55, 0.1),
	]
	for i in 6:
		var p := CPUParticles2D.new()
		p.z_index = 7
		p.amount = 18
		p.lifetime = 2.0
		p.explosiveness = 0.9
		p.randomness = 0.9
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 12.0
		p.position = size * 0.5 + Vector2(randf_range(-40, 40), randf_range(-30, 30))
		p.direction = Vector2(randf_range(-1, 1), randf_range(-1, 0.2)).normalized()
		p.spread = 180.0
		p.gravity = Vector2(0, 90)
		p.initial_velocity_min = 80.0
		p.initial_velocity_max = 220.0
		p.scale_amount_min = 2.5
		p.scale_amount_max = 5.5
		p.color = colors[i % colors.size()]
		p.texture = _chaos_soft_tex(4)
		_chaos_layer.add_child(p)
		p.emitting = true
		# Stop emission after burst
		var t := get_tree().create_timer(0.35)
		t.timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.emitting = false
		)


func _chaos_floating_text(msg: String, col: Color, font_delta: int = 8) -> void:
	var lbl := Label.new()
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", _ed_font(font_delta))
	lbl.add_theme_color_override("font_color", col)
	lbl.z_index = 20
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chaos_layer.add_child(lbl)
	# Center then float
	lbl.reset_size()
	lbl.position = Vector2(size.x * 0.5 - lbl.size.x * 0.5, size.y * 0.35)
	lbl.modulate = Color(1, 1, 1, 0)
	lbl.scale = Vector2(0.3, 0.3)
	lbl.pivot_offset = lbl.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.12)
	tw.tween_property(lbl, "scale", Vector2(1.35, 1.35), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().set_parallel(false)
	tw.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.15)
	tw.tween_property(lbl, "position:y", lbl.position.y - 50.0, 1.2)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 1.0).set_delay(0.5)
	tw.tween_callback(lbl.queue_free)


func _chaos_rain_emojis(emojis: Array, count: int = 16) -> void:
	if not _chaos_emojis:
		return
	count = clampi(int(count * _chaos_intensity), 4, 40)
	for i in count:
		var e := Label.new()
		e.text = str(emojis[i % emojis.size()])
		e.add_theme_font_size_override("font_size", _ed_font(4 + randi() % 6))
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		e.z_index = 15
		_chaos_layer.add_child(e)
		e.position = Vector2(randf_range(8, maxf(size.x - 40, 20)), randf_range(-40, size.y * 0.2))
		e.rotation = randf_range(-0.6, 0.6)
		e.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(e, "modulate:a", 1.0, 0.1)
		tw.parallel().tween_property(e, "position", e.position + Vector2(randf_range(-40, 40), size.y * 0.55 + randf_range(0, 80)), randf_range(1.2, 2.4)).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(e, "rotation", e.rotation + randf_range(-2.5, 2.5), 1.8)
		tw.tween_property(e, "modulate:a", 0.0, 0.4)
		tw.tween_callback(e.queue_free)


func _chaos_fx_explode(targets: Array) -> void:
	# Triple flash BOOM
	for i in 3:
		var flash := ColorRect.new()
		flash.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		flash.color = Color(1, 0.92, 0.7, 0.0)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_chaos_layer.add_child(flash)
		var tf := create_tween()
		tf.tween_interval(i * 0.07)
		tf.tween_property(flash, "color:a", 0.9 - i * 0.2, 0.05)
		tf.tween_property(flash, "color:a", 0.0, 0.28)
		tf.tween_callback(flash.queue_free)

	_chaos_floating_text("BOOOOM 💥", Color(1.0, 0.55, 0.15), 10)
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		if is_instance_valid(_chaos_layer):
			_chaos_floating_text(tr_ui("chaos_boom_line"), Color(1.0, 0.85, 0.3), 3)
	)

	_chaos_spawn_smoke(Color(0.5, 0.5, 0.55, 0.6), 80, true)
	_chaos_spawn_embers(Color(1.0, 0.65, 0.15, 0.95), 55)
	_chaos_spawn_confetti()
	_chaos_rain_emojis(["💥", "💫", "⭐", "✨", "🌪️", "💣"], 20)

	for n in targets:
		if not is_instance_valid(n) or not (n is Control):
			continue
		var c := n as Control
		var ang := randf_range(-3.5, 3.5)
		var k := clampf(_chaos_intensity, 0.5, 2.5)
		var off := Vector2(randf_range(-220, 220) * k, randf_range(-160, 200) * k)
		var sc := Vector2(randf_range(0.25, 1.6) * (0.7 + k * 0.3), randf_range(0.25, 1.6) * (0.7 + k * 0.3))
		var delay := randf_range(0.0, 0.2)
		var tw := _chaos_make_tween()
		tw.tween_interval(delay)
		tw.set_parallel(true)
		tw.tween_property(c, "position", c.position + off, randf_range(0.5, 1.1)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "rotation", ang, randf_range(0.45, 1.0)).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(c, "scale", sc, randf_range(0.4, 0.85))
		# Alpha reste à 1.0 pour éviter UI « morte » si restore interrompu
		tw.tween_property(c, "modulate", Color(1, 0.55 + randf() * 0.3, 0.2, 1.0), 0.55)
		# Rebond secondaire
		tw.chain().set_parallel(true)
		tw.tween_property(c, "position", c.position + off * 1.15 + Vector2(randf_range(-30, 30), randf_range(10, 40)), 0.35)
		tw.tween_property(c, "rotation", ang + randf_range(-0.4, 0.4), 0.35)


func _chaos_fx_burn(targets: Array) -> void:
	var heat := ColorRect.new()
	heat.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	heat.color = Color(1.0, 0.25, 0.05, 0.0)
	heat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chaos_layer.add_child(heat)
	var th := _chaos_make_tween()
	th.tween_property(heat, "color:a", 0.35, 0.4)
	th.tween_property(heat, "color:a", 0.15, 1.5)
	th.tween_property(heat, "color:a", 0.25, 0.8)

	_chaos_floating_text("🔥  " + tr_ui("chaos_burn_line"), Color(1.0, 0.4, 0.1), 6)
	_chaos_spawn_smoke(Color(0.22, 0.18, 0.15, 0.55), 90, true)
	_chaos_spawn_embers(Color(1.0, 0.4, 0.05, 0.95), 60)
	# 2e vague de fumée plus lente
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		if is_instance_valid(_chaos_layer) and _chaos_active:
			_chaos_spawn_smoke(Color(0.3, 0.28, 0.25, 0.4), 40, true)
	)
	_chaos_rain_emojis(["🔥", "🥵", "💨", "🌋", "🧯", "☕"], 18)

	for n in targets:
		if not is_instance_valid(n) or not (n is CanvasItem):
			continue
		var ci := n as CanvasItem
		# Boucles limitées + couleurs non « noires » (alpha reste 1.0 pour éviter UI morte)
		var tw := _chaos_make_tween()
		tw.set_loops(4)
		var hot := Color(1.0, 0.45 + randf() * 0.3, 0.12, 1.0)
		var charred := Color(0.55, 0.28, 0.12, 1.0)  # brun chaud, pas noir
		tw.tween_property(ci, "modulate", hot, 0.28 + randf() * 0.2)
		tw.tween_property(ci, "modulate", charred, 0.4 + randf() * 0.25)
		if n is Control:
			var c := n as Control
			var base := c.position
			var shake := _chaos_make_tween()
			shake.set_loops(8)
			shake.tween_property(c, "position", base + Vector2(randf_range(-5, 5), randf_range(-4, 4)), 0.06)
			shake.tween_property(c, "position", base + Vector2(randf_range(-3, 3), randf_range(-2, 2)), 0.06)
			# Légère « fonte »
			var melt := _chaos_make_tween()
			melt.tween_property(c, "scale", Vector2(1.05, 0.88), 1.2).set_trans(Tween.TRANS_SINE)
			melt.tween_property(c, "scale", Vector2(1.08, 0.82), 1.0)


func _chaos_fx_freeze(targets: Array) -> void:
	var ice := ColorRect.new()
	ice.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	ice.color = Color(0.55, 0.85, 1.0, 0.0)
	ice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chaos_layer.add_child(ice)
	var ti := create_tween()
	ti.tween_property(ice, "color:a", 0.4, 0.5)
	ti.tween_property(ice, "color:a", 0.22, 1.2)

	# Cristaux « crack » — flashs brefs
	for i in 4:
		var crack := ColorRect.new()
		crack.color = Color(0.85, 0.95, 1.0, 0.0)
		crack.size = Vector2(randf_range(40, 120), randf_range(2, 6))
		crack.position = Vector2(randf_range(0, maxf(size.x - 40, 10)), randf_range(0, maxf(size.y - 10, 10)))
		crack.rotation = randf_range(-0.8, 0.8)
		crack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_chaos_layer.add_child(crack)
		var tc := create_tween()
		tc.tween_interval(0.1 + i * 0.12)
		tc.tween_property(crack, "color:a", 0.85, 0.05)
		tc.tween_property(crack, "color:a", 0.0, 0.35)
		tc.tween_callback(crack.queue_free)

	_chaos_floating_text("❄️  " + tr_ui("chaos_freeze_line"), Color(0.6, 0.9, 1.0), 6)
	_chaos_spawn_smoke(Color(0.8, 0.92, 1.0, 0.5), 70, false)
	var snow := _chaos_spawn_embers(Color(0.9, 0.97, 1.0, 0.9), 50)
	if is_instance_valid(snow):
		snow.gravity = Vector2(0, 35)
		snow.direction = Vector2(0, 1)
		snow.initial_velocity_min = 10.0
		snow.initial_velocity_max = 50.0
	_chaos_rain_emojis(["❄️", "🧊", "🐧", "🥶", "☃️", "🌨️"], 18)

	for n in targets:
		if not is_instance_valid(n) or not (n is CanvasItem):
			continue
		var ci := n as CanvasItem
		var frosty := Color(0.65, 0.88, 1.0, 1.0)  # alpha 1.0 — pas de fade grisé
		var tw := _chaos_make_tween()
		tw.tween_property(ci, "modulate", frosty, 0.6 + randf() * 0.5).set_trans(Tween.TRANS_SINE)
		if n is Control:
			var c := n as Control
			var ts := _chaos_make_tween()
			ts.tween_property(c, "scale", Vector2(1.0, 0.9), 0.55)
			ts.tween_property(c, "scale", Vector2(1.04, 0.94), 0.5)
			# Micro-gel (rotation bloquée + tremblement glacé)
			var sh := _chaos_make_tween()
			sh.set_loops(4)
			var base := c.position
			sh.tween_property(c, "position", base + Vector2(randf_range(-1.5, 1.5), 0), 0.12)
			sh.tween_property(c, "position", base, 0.12)



func _chaos_fx_pressure(targets: Array) -> void:
	## Urgence critique : sirène, compte à rebours, pression qui monte, panic UI.
	# Fond alarme
	var alert := ColorRect.new()
	alert.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	alert.color = Color(0.55, 0.0, 0.05, 0.0)
	alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chaos_layer.add_child(alert)
	var ta := create_tween()
	ta.set_loops(12)
	ta.tween_property(alert, "color:a", 0.42, 0.18)
	ta.tween_property(alert, "color:a", 0.08, 0.18)

	# Bandes hazard (haut + bas)
	for top in [true, false]:
		var stripe := ColorRect.new()
		stripe.color = Color(1.0, 0.85, 0.0, 0.0)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stripe.z_index = 8
		_chaos_layer.add_child(stripe)
		stripe.size = Vector2(size.x + 40, 18)
		stripe.position = Vector2(-20, 0 if top else maxf(size.y - 18, 0))
		var ts := create_tween()
		ts.tween_property(stripe, "color:a", 0.9, 0.15)
		ts.set_parallel(true)
		# Scroll illusion
		ts.tween_property(stripe, "position:x", 20.0, 0.4).as_relative()
		var pulse := create_tween()
		pulse.set_loops(10)
		pulse.tween_property(stripe, "color", Color(1.0, 0.2, 0.05, 0.85), 0.2)
		pulse.tween_property(stripe, "color", Color(1.0, 0.9, 0.0, 0.7), 0.2)

	# Gros titre CRITICAL
	_chaos_floating_text("🚨  CRITICAL", Color(1.0, 0.15, 0.15), 11)
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		if is_instance_valid(_chaos_layer) and _chaos_active:
			_chaos_floating_text(tr_ui("chaos_pressure_line"), Color(1.0, 0.85, 0.2), 4)
	)

	# Compte à rebours 5 → 0
	var countdown := Label.new()
	countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown.add_theme_font_size_override("font_size", _ed_font(14))
	countdown.add_theme_color_override("font_color", Color(1.0, 0.2, 0.15))
	countdown.z_index = 25
	countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chaos_layer.add_child(countdown)
	countdown.text = "5"
	countdown.reset_size()
	countdown.pivot_offset = countdown.size * 0.5
	countdown.position = Vector2(size.x * 0.5 - countdown.size.x * 0.5, size.y * 0.42)
	countdown.scale = Vector2(0.5, 0.5)
	for n in range(5, -1, -1):
		var step := 5 - n
		var tcd := get_tree().create_timer(0.15 + step * 0.85)
		tcd.timeout.connect(func() -> void:
			if not is_instance_valid(countdown) or not _chaos_active:
				return
			countdown.text = str(n) if n > 0 else "!!!"
			countdown.reset_size()
			countdown.pivot_offset = countdown.size * 0.5
			countdown.position = Vector2(size.x * 0.5 - countdown.size.x * 0.5, size.y * 0.42)
			countdown.scale = Vector2(0.4, 0.4)
			countdown.modulate = Color(1, 0.15, 0.1, 1)
			var twc := create_tween()
			twc.tween_property(countdown, "scale", Vector2(1.4, 1.4), 0.2).set_trans(Tween.TRANS_BACK)
			twc.tween_property(countdown, "scale", Vector2(1.0, 1.0), 0.15)
			if n == 0:
				_chaos_screen_punch()
				_chaos_floating_text(tr_ui("chaos_pressure_zero"), Color(1.0, 0.3, 0.1), 5)
		)

	# Barre de pression qui monte
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.1, 0.05, 0.05, 0.85)
	bar_bg.size = Vector2(maxi(size.x * 0.7, 120), 14)
	bar_bg.position = Vector2(size.x * 0.15, size.y * 0.62)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.z_index = 12
	_chaos_layer.add_child(bar_bg)
	var bar_fg := ColorRect.new()
	bar_fg.color = Color(1.0, 0.2, 0.1, 1.0)
	bar_fg.size = Vector2(4, 14)
	bar_fg.position = bar_bg.position
	bar_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_fg.z_index = 13
	_chaos_layer.add_child(bar_fg)
	var bar_lbl := Label.new()
	bar_lbl.text = tr_ui("chaos_pressure_bar")
	bar_lbl.add_theme_font_size_override("font_size", _ed_font(-1))
	bar_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	bar_lbl.position = Vector2(bar_bg.position.x, bar_bg.position.y - 22)
	bar_lbl.z_index = 13
	bar_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chaos_layer.add_child(bar_lbl)
	var tb := create_tween()
	tb.tween_property(bar_fg, "size:x", bar_bg.size.x, 5.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tb.parallel().tween_property(bar_fg, "color", Color(1.0, 0.05, 0.05, 1.0), 5.5)

	# Particules « alarme »
	_chaos_spawn_smoke(Color(0.6, 0.1, 0.1, 0.45), 50, true)
	_chaos_spawn_embers(Color(1.0, 0.25, 0.1, 0.9), 45)
	_chaos_rain_emojis(["🚨", "⚠️", "🔴", "📢", "⏱️", "💀"], 22)

	# Messages panic en rafale
	var panic_keys := ["chaos_pressure_p1", "chaos_pressure_p2", "chaos_pressure_p3", "chaos_pressure_p4"]
	for i in panic_keys.size():
		var key: String = panic_keys[i]
		get_tree().create_timer(0.9 + i * 1.1).timeout.connect(func() -> void:
			if is_instance_valid(_chaos_layer) and _chaos_active:
				_chaos_floating_text(tr_ui(key), Color(1.0, 0.5 + i * 0.1, 0.2), 3)
		)

	# UI qui pulse rouge + heartbeat shake
	for n in targets:
		if not is_instance_valid(n) or not (n is CanvasItem):
			continue
		var ci := n as CanvasItem
		var tw := _chaos_make_tween()
		tw.set_loops(8)
		tw.tween_property(ci, "modulate", Color(1.0, 0.25, 0.2, 1.0), 0.22)
		tw.tween_property(ci, "modulate", Color(0.9, 0.2, 0.15, 1.0), 0.22)  # alpha 1.0
		if n is Control:
			var c := n as Control
			var base := c.position
			var hb := _chaos_make_tween()
			hb.set_loops(12)
			# Battement : petit → fort → petit
			hb.tween_property(c, "scale", Vector2(1.04, 1.04), 0.12)
			hb.tween_property(c, "scale", Vector2(1.0, 1.0), 0.12)
			hb.tween_property(c, "scale", Vector2(1.07, 1.07), 0.1)
			hb.tween_property(c, "scale", Vector2(1.0, 1.0), 0.18)
			hb.tween_interval(0.15)
			var sh := _chaos_make_tween()
			sh.set_loops(15)
			sh.tween_property(c, "position", base + Vector2(randf_range(-4, 4), randf_range(-3, 3)), 0.05)
			sh.tween_property(c, "position", base, 0.05)

	# Sirène visuelle finale (cercles)
	for i in 5:
		get_tree().create_timer(0.3 + i * 0.55).timeout.connect(func() -> void:
			if not is_instance_valid(_chaos_layer) or not _chaos_active:
				return
			var ring := ColorRect.new()
			ring.color = Color(1.0, 0.15, 0.1, 0.55)
			ring.size = Vector2(20, 20)
			ring.position = size * 0.5 - ring.size * 0.5
			ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ring.z_index = 9
			_chaos_layer.add_child(ring)
			var tr := create_tween()
			tr.set_parallel(true)
			tr.tween_property(ring, "size", Vector2(size.x * 1.2, size.y * 1.2), 0.7)
			tr.tween_property(ring, "position", size * 0.5 - Vector2(size.x * 0.6, size.y * 0.6), 0.7)
			tr.tween_property(ring, "color:a", 0.0, 0.7)
			tr.chain().tween_callback(ring.queue_free)
		)


func _chaos_fx_matrix(targets: Array) -> void:
	## Pluie digitale Matrix + glitch vert + langage Yautja.
	var green := Color(0.15, 0.95, 0.35)
	var dark := Color(0.02, 0.08, 0.03, 0.72)
	# Overlay vert sombre
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	overlay.color = dark
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 5
	_chaos_layer.add_child(overlay)
	# Digital rain — colonnes de caractères
	const RAIN_CHARS := "01アイウエオカキクケコサシスセソタチツテトナニヌネノﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝꖌꖎꖒꖔᚠᚢ"
	var cols := clampi(int(size.x / 14.0), 8, 28)
	for c in cols:
		var col_x := 6.0 + c * (size.x / float(cols))
		var trail_len := 6 + randi() % 10
		for row in trail_len:
			var lbl := Label.new()
			lbl.text = RAIN_CHARS[randi() % RAIN_CHARS.length()]
			lbl.add_theme_font_size_override("font_size", _ed_font(-1 + randi() % 3))
			var alpha := clampf(1.0 - float(row) / float(trail_len), 0.15, 1.0)
			lbl.add_theme_color_override("font_color", Color(green.r, green.g, green.b, alpha))
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lbl.z_index = 12
			_chaos_layer.add_child(lbl)
			var start_y := -30.0 - randf() * 80.0 - row * 16.0
			lbl.position = Vector2(col_x + randf_range(-4, 4), start_y)
			var fall := size.y + 60.0 + randf() * 40.0
			var dur := randf_range(1.8, 3.8) * clampf(_chaos_duration_mult, 0.6, 1.8)
			var tw := create_tween()
			tw.tween_property(lbl, "position:y", fall, dur).set_trans(Tween.TRANS_LINEAR)
			tw.parallel().tween_property(lbl, "modulate:a", 0.0, dur * 0.35).set_delay(dur * 0.65)
			tw.tween_callback(lbl.queue_free)
			# Refresh glyph mid-fall
			if randf() < 0.5:
				get_tree().create_timer(dur * 0.35).timeout.connect(func() -> void:
					if is_instance_valid(lbl):
						lbl.text = RAIN_CHARS[randi() % RAIN_CHARS.length()]
				)
	# Titres flottants
	_chaos_floating_text(tr_ui("chaos_matrix_line"), green, 6)
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if is_instance_valid(_chaos_layer) and _chaos_active:
			_chaos_floating_text(_yautja_flavor("WAKE UP"), green.lightened(0.2), 4)
	)
	get_tree().create_timer(1.1).timeout.connect(func() -> void:
		if is_instance_valid(_chaos_layer) and _chaos_active:
			_chaos_floating_text(tr_ui("chaos_matrix_line2"), green, 3)
	)
	# Glitch léger sur les cibles
	var k := clampf(_chaos_intensity, 0.5, 2.2)
	for n in targets:
		if not is_instance_valid(n) or not (n is CanvasItem):
			continue
		var ci := n as CanvasItem
		var twg := _chaos_make_tween()
		twg.set_loops(clampi(int(6 * k), 3, 12))
		twg.tween_property(ci, "modulate", Color(0.4, 1.0, 0.5, 0.85), 0.06)
		twg.tween_property(ci, "modulate", Color(0.85, 1.0, 0.9, 1.0), 0.08)
		twg.tween_property(ci, "position:x", ci.position.x + randf_range(-3, 3) * k, 0.04)
		twg.tween_property(ci, "position:x", ci.position.x, 0.05)


func _chaos_fx_terminator(targets: Array) -> void:
	## HUD Terminator rouge : scanlines, TARGET ACQUIRED, compte à rebours style T-800.
	var red := Color(0.95, 0.12, 0.10)
	var red_dim := Color(0.35, 0.04, 0.03, 0.78)
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	overlay.color = red_dim
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 5
	_chaos_layer.add_child(overlay)
	# Scanlines horizontales
	var line_count := clampi(int(size.y / 22.0), 6, 18)
	for i in line_count:
		var line := ColorRect.new()
		line.color = Color(0.9, 0.1, 0.08, 0.18 + randf() * 0.15)
		line.size = Vector2(size.x + 20, 1 + randi() % 2)
		line.position = Vector2(-10, i * (size.y / float(line_count)) + randf_range(-4, 4))
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.z_index = 7
		_chaos_layer.add_child(line)
		var twl := create_tween()
		twl.set_loops(8)
		twl.tween_property(line, "color:a", 0.35, 0.15)
		twl.tween_property(line, "color:a", 0.08, 0.2)
	# Barre de scan verticale qui traverse
	var scanner := ColorRect.new()
	scanner.color = Color(1.0, 0.2, 0.12, 0.55)
	scanner.size = Vector2(4, size.y)
	scanner.position = Vector2(-8, 0)
	scanner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scanner.z_index = 14
	_chaos_layer.add_child(scanner)
	var tws := create_tween()
	tws.set_loops(3)
	tws.tween_property(scanner, "position:x", size.x + 10.0, 1.1).set_trans(Tween.TRANS_LINEAR)
	tws.tween_property(scanner, "position:x", -8.0, 0.02)
	# Coins HUD (cadrage)
	for corner in [
		Vector2(8, 8), Vector2(size.x - 40, 8),
		Vector2(8, size.y - 28), Vector2(size.x - 40, size.y - 28)
	]:
		var bracket := Label.new()
		bracket.text = "⌜" if corner.x < size.x * 0.5 and corner.y < size.y * 0.5 else (
			"⌝" if corner.x > size.x * 0.5 and corner.y < size.y * 0.5 else (
			"⌞" if corner.x < size.x * 0.5 else "⌟"))
		bracket.add_theme_font_size_override("font_size", _ed_font(8))
		bracket.add_theme_color_override("font_color", red)
		bracket.position = corner
		bracket.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bracket.z_index = 15
		_chaos_layer.add_child(bracket)
	# Messages
	_chaos_floating_text(tr_ui("chaos_terminator_line"), red, 7)
	get_tree().create_timer(0.45).timeout.connect(func() -> void:
		if is_instance_valid(_chaos_layer) and _chaos_active:
			_chaos_floating_text(tr_ui("chaos_terminator_line2"), Color(1.0, 0.5, 0.35), 4)
	)
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(_chaos_layer) and _chaos_active:
			_chaos_floating_text("I'LL BE BACK", red.lightened(0.15), 5)
	)
	# Pulse rouge sur les cibles
	var k := clampf(_chaos_intensity, 0.5, 2.2)
	for n in targets:
		if not is_instance_valid(n) or not (n is CanvasItem):
			continue
		var ci := n as CanvasItem
		var twg := _chaos_make_tween()
		twg.set_loops(clampi(int(5 * k), 3, 10))
		twg.tween_property(ci, "modulate", Color(1.0, 0.35, 0.3, 0.9), 0.12)
		twg.tween_property(ci, "modulate", Color(1.0, 0.85, 0.85, 1.0), 0.18)
	if _chaos_emojis:
		_chaos_rain_emojis(["🤖", "🔴", "👁️", "⚙️", "💀", "🎯"], 14)


func _chaos_restore() -> void:
	if not _chaos_active and _chaos_saved.is_empty():
		_chaos_close_menu()
		if is_instance_valid(_chaos_btn):
			_chaos_btn.text = tr_ui("chaos_btn")
		return
	_chaos_active = false
	_chaos_kind = ""

	# CRITIQUE : tuer tous les tweens Chaos (boucles burn/pressure) avant restore
	# sinon le modulate « charbon » continue d’écraser la restauration → UI noire.
	_chaos_kill_tweens()

	# Petit « whoosh » de restauration
	if is_instance_valid(_chaos_layer):
		_chaos_floating_text(tr_ui("chaos_restore_line"), Color(0.4, 0.9, 0.5), 4)

	for entry in _chaos_saved:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var n = entry.get("node", null)
		if not is_instance_valid(n):
			continue
		var ci := n as CanvasItem
		var target_mod: Color = entry.get("modulate", Color.WHITE)
		# Force immédiate du modulate (évite flash noir si un tween zombie restait)
		ci.modulate = target_mod
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(ci, "modulate", target_mod, 0.35).set_trans(Tween.TRANS_SINE)
		if n is Control:
			var c := n as Control
			var target_pos: Vector2 = entry.get("position", c.position)
			var target_rot: float = entry.get("rotation", 0.0)
			var target_sc: Vector2 = entry.get("scale", Vector2.ONE)
			c.position = target_pos
			c.rotation = target_rot
			c.scale = target_sc
			tw.tween_property(c, "position", target_pos, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(c, "rotation", target_rot, 0.4).set_trans(Tween.TRANS_BACK)
			tw.tween_property(c, "scale", target_sc, 0.4).set_trans(Tween.TRANS_ELASTIC)
	_chaos_saved.clear()

	if is_instance_valid(_chaos_smoke):
		_chaos_smoke.emitting = false
		if is_instance_valid(_chaos_smoke):
			_chaos_smoke.queue_free()
		_chaos_smoke = null
	if is_instance_valid(_chaos_embers):
		_chaos_embers.emitting = false
		if is_instance_valid(_chaos_embers):
			_chaos_embers.queue_free()
		_chaos_embers = null
	if is_instance_valid(_chaos_layer):
		var layer := _chaos_layer
		_chaos_layer = null
		var tf := create_tween()
		tf.tween_property(layer, "modulate:a", 0.0, 0.35)
		tf.tween_callback(func() -> void:
			if is_instance_valid(layer):
				layer.queue_free()
		)

	# Reset scale dock (punch) — position laissée au layout
	scale = Vector2.ONE
	var tr := create_tween()
	tr.tween_property(self, "scale", Vector2.ONE, 0.2)

	if is_instance_valid(_chaos_btn):
		_chaos_btn.text = tr_ui("chaos_btn")
	_feedback(tr_ui("chaos_restored"), "ok")
	_log(tr_ui("chaos_restored"), "ok")


func _on_coffee_break() -> void:
	if _coffee_active:
		_hide_coffee_break()
		return
	_show_break_menu()


func _show_break_menu() -> void:
	## Choix de l'activité de pause avant l'animation 3D.
	if is_instance_valid(_coffee_layer):
		_coffee_layer.queue_free()
		_coffee_layer = null
	_coffee_active = false

	_coffee_layer = Control.new()
	_coffee_layer.name = "BreakMenuLayer"
	_coffee_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_coffee_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_coffee_layer.z_index = 250
	add_child(_coffee_layer)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.03, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_coffee_layer.add_child(dim)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 10)
	_coffee_layer.add_child(center)

	var title := Label.new()
	title.text = tr_ui("break_menu_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", _ed_font(5))
	title.add_theme_color_override("font_color", C_PRIMARY)
	center.add_child(title)

	var sub := Label.new()
	sub.text = tr_ui("break_menu_sub")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", _ed_font(-1))
	sub.add_theme_color_override("font_color", C_MUTED)
	center.add_child(sub)

	var grid := HFlowContainer.new()
	grid.alignment = 1  # ALIGNMENT_CENTER
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	center.add_child(grid)

	var kinds := [
		["coffee", "break_coffee"],
		["cola", "break_cola"],
		["pizza", "break_pizza"],
		["cigarette", "break_cigarette"],
		["marijuana", "break_marijuana"],
	]
	for pair in kinds:
		var kind: String = pair[0]
		var key: String = pair[1]
		var b := Button.new()
		b.text = tr_ui(key)
		b.custom_minimum_size = Vector2(120, 36)
		b.pressed.connect(_on_break_kind_chosen.bind(kind))
		grid.add_child(b)
		_style_secondary_button(b)

	var cancel := Button.new()
	cancel.text = tr_ui("break_cancel")
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_hide_coffee_break)
	center.add_child(cancel)
	_style_primary_button(cancel)

	_coffee_layer.modulate = Color(1, 1, 1, 0)
	var t := create_tween()
	t.tween_property(_coffee_layer, "modulate:a", 1.0, 0.25)


func _on_break_kind_chosen(kind: String) -> void:
	_break_kind = kind
	_show_coffee_break()


func _show_coffee_break() -> void:
	if is_instance_valid(_coffee_layer):
		_coffee_layer.queue_free()
		_coffee_layer = null
	_coffee_active = true
	_coffee_heat = 0.0
	# Masquer mascotte si présente
	if _mascot_visible and is_instance_valid(_mascot_root):
		_mascot_hide_timer.stop()
		_mascot_stop_idle()
		if _mascot_tween and _mascot_tween.is_valid():
			_mascot_tween.kill()
		_mascot_root.visible = false
		_mascot_bubble.visible = false
		_mascot_visible = false

	_coffee_layer = Control.new()
	_coffee_layer.name = "BreakLayer"
	_coffee_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_coffee_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_coffee_layer.z_index = 250
	add_child(_coffee_layer)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.03, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_coffee_layer.add_child(dim)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 10)
	_coffee_layer.add_child(center)

	var title := Label.new()
	title.text = tr_ui("break_title_" + _break_kind)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", _ed_font(5))
	title.add_theme_color_override("font_color", C_PRIMARY)
	center.add_child(title)

	var msg := Label.new()
	msg.text = tr_ui("break_msg_" + _break_kind)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", _ed_font())
	msg.add_theme_color_override("font_color", C_TEXT)
	center.add_child(msg)
	_break_msg_label = msg
	_break_phase = 0.0
	_break_sip_t = 0.0

	# Avertissement santé / légal (clope & marijuana)
	_break_warn_label = Label.new()
	_break_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_break_warn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_break_warn_label.add_theme_font_size_override("font_size", _ed_font(-1))
	_break_warn_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.35))
	_break_warn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_break_warn_label.custom_minimum_size = Vector2(260, 0)
	if _break_kind == "cigarette":
		_break_warn_label.text = tr_ui("break_warn_cigarette")
	elif _break_kind == "marijuana":
		_break_warn_label.text = tr_ui("break_warn_marijuana")
	else:
		_break_warn_label.text = ""
		_break_warn_label.visible = false
	center.add_child(_break_warn_label)

	# Viewport 3D — config robuste pour le dock éditeur
	var vp_frame := PanelContainer.new()
	vp_frame.custom_minimum_size = Vector2(280, 280)
	vp_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var frame_sb := StyleBoxFlat.new()
	frame_sb.bg_color = Color(0.08, 0.09, 0.11, 1.0)
	frame_sb.set_corner_radius_all(12)
	frame_sb.content_margin_left = 4
	frame_sb.content_margin_right = 4
	frame_sb.content_margin_top = 4
	frame_sb.content_margin_bottom = 4
	frame_sb.border_width_left = 1
	frame_sb.border_width_right = 1
	frame_sb.border_width_top = 1
	frame_sb.border_width_bottom = 1
	frame_sb.border_color = Color(0.25, 0.26, 0.30)
	vp_frame.add_theme_stylebox_override("panel", frame_sb)
	center.add_child(vp_frame)

	var vp_box := SubViewportContainer.new()
	vp_box.stretch = true
	vp_box.custom_minimum_size = Vector2(272, 272)
	vp_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vp_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vp_frame.add_child(vp_box)

	var vp := SubViewport.new()
	vp.name = "BreakViewport"
	vp.size = Vector2i(272, 272)
	vp.own_world_3d = true
	vp.transparent_bg = false  # fond opaque = rendu fiable dans le dock
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.handle_input_locally = false
	vp.msaa_3d = Viewport.MSAA_2X
	vp_box.add_child(vp)

	var world := Node3D.new()
	world.name = "BreakWorld"
	vp.add_child(world)

	# Environnement : lumière ambiante pour éviter un rendu tout noir
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	world.add_child(we)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 42.0
	cam.near = 0.05
	cam.far = 50.0
	# Ajouter à l’arbre avant look_at (requis hors scene tree)
	cam.position = Vector3(1.15, 1.05, 1.45)
	world.add_child(cam)
	cam.look_at(Vector3(0.0, 0.35, 0.0), Vector3.UP)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.light_energy = 1.35
	sun.shadow_enabled = false
	world.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.7, 0.8, 1.0)
	world.add_child(fill)

	_coffee_glow = OmniLight3D.new()
	_coffee_glow.position = Vector3(0.2, 0.9, 0.4)
	_coffee_glow.light_energy = 0.85
	_coffee_glow.light_color = Color(1.0, 0.65, 0.35)
	_coffee_glow.omni_range = 3.5
	_coffee_glow.omni_attenuation = 1.2
	world.add_child(_coffee_glow)

	# Sol discret pour ancrer l’objet
	var floor_mi := MeshInstance3D.new()
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 0.95
	floor_mesh.bottom_radius = 0.95
	floor_mesh.height = 0.03
	floor_mi.mesh = floor_mesh
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.16, 0.17, 0.20)
	floor_mat.roughness = 0.85
	floor_mi.material_override = floor_mat
	floor_mi.position = Vector3(0, -0.01, 0)
	world.add_child(floor_mi)

	_coffee_cup = Node3D.new()
	_coffee_cup.name = "BreakProp"
	world.add_child(_coffee_cup)

	match _break_kind:
		"cola":
			_break_build_cola(_coffee_cup)
		"pizza":
			_break_build_pizza(_coffee_cup)
		"cigarette":
			_break_build_cigarette(_coffee_cup)
		"marijuana":
			_break_build_marijuana(_coffee_cup)
		_:
			_break_build_coffee(_coffee_cup)

	# Forcer une première frame (parfois nécessaire dans l’éditeur)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	center.add_child(row)

	var back := Button.new()
	back.text = tr_ui("break_other")
	back.pressed.connect(_show_break_menu)
	row.add_child(back)
	_style_secondary_button(back)

	var done := Button.new()
	done.text = tr_ui("coffee_done")
	done.pressed.connect(_hide_coffee_break)
	row.add_child(done)
	_style_primary_button(done)

	_coffee_layer.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(_coffee_layer, "modulate:a", 1.0, 0.3)

	if not is_processing():
		set_process(true)


func _break_mat(color: Color, rough: float = 0.45, metallic: float = 0.0, emission: Color = Color(0, 0, 0, 0), emission_e: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = clampf(rough, 0.15, 1.0)
	m.metallic = clampf(metallic, 0.0, 1.0)
	m.specular = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # visible sous tous les angles dans le dock
	if emission_e > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_e
	return m


func _break_build_coffee(root: Node3D) -> void:
	var mat_body := _break_mat(Color(0.92, 0.92, 0.94), 0.35)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.32
	cyl.bottom_radius = 0.28
	cyl.height = 0.55
	body.mesh = cyl
	body.material_override = mat_body
	body.position = Vector3(0, 0.30, 0)
	body.name = "CupBody"
	root.add_child(body)

	var liquid := MeshInstance3D.new()
	var lcyl := CylinderMesh.new()
	lcyl.top_radius = 0.26
	lcyl.bottom_radius = 0.26
	lcyl.height = 0.08
	liquid.mesh = lcyl
	liquid.material_override = _break_mat(Color(0.28, 0.14, 0.06), 0.55, 0.0, Color(0.45, 0.2, 0.05), 0.4)
	liquid.position = Vector3(0, 0.48, 0)
	liquid.name = "Liquid"
	root.add_child(liquid)

	var handle := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.08
	torus.outer_radius = 0.18
	torus.rings = 16
	torus.ring_segments = 12
	handle.mesh = torus
	handle.material_override = mat_body
	handle.position = Vector3(0.42, 0.32, 0)
	handle.rotation_degrees = Vector3(0, 0, 90)
	root.add_child(handle)

	var saucer := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.55
	disc.height = 0.04
	saucer.mesh = disc
	saucer.material_override = _break_mat(Color(0.88, 0.88, 0.90), 0.4)
	saucer.position = Vector3(0, 0.02, 0)
	root.add_child(saucer)
	_break_add_steam(root, Vector3(0, 0.58, 0), Color(0.9, 0.9, 0.95, 0.45))


func _break_build_cola(root: Node3D) -> void:
	# Canette
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.22
	cyl.height = 0.75
	body.mesh = cyl
	body.material_override = _break_mat(Color(0.75, 0.08, 0.10), 0.35, 0.55)
	body.position = Vector3(0, 0.40, 0)
	body.name = "CanBody"
	root.add_child(body)
	var top := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.20
	tc.bottom_radius = 0.22
	tc.height = 0.06
	top.mesh = tc
	top.material_override = _break_mat(Color(0.75, 0.75, 0.78), 0.3, 0.8)
	top.position = Vector3(0, 0.80, 0)
	root.add_child(top)
	var label := MeshInstance3D.new()
	var band := CylinderMesh.new()
	band.top_radius = 0.225
	band.bottom_radius = 0.225
	band.height = 0.18
	label.mesh = band
	label.material_override = _break_mat(Color(0.95, 0.95, 0.97), 0.4)
	label.position = Vector3(0, 0.42, 0)
	root.add_child(label)
	_break_add_steam(root, Vector3(0, 0.88, 0), Color(0.85, 0.9, 1.0, 0.35))  # bulles / fraîcheur
	if is_instance_valid(_coffee_glow):
		_coffee_glow.light_color = Color(0.9, 0.25, 0.2)


func _break_build_pizza(root: Node3D) -> void:
	var base := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.62
	disc.bottom_radius = 0.62
	disc.height = 0.06
	base.mesh = disc
	base.material_override = _break_mat(Color(0.85, 0.65, 0.28), 0.7)
	base.position = Vector3(0, 0.08, 0)
	base.name = "PizzaBase"
	root.add_child(base)
	var sauce := MeshInstance3D.new()
	var sd := CylinderMesh.new()
	sd.top_radius = 0.55
	sd.bottom_radius = 0.55
	sd.height = 0.03
	sauce.mesh = sd
	sauce.material_override = _break_mat(Color(0.75, 0.18, 0.12), 0.6, 0.0, Color(0.6, 0.15, 0.05), 0.15)
	sauce.position = Vector3(0, 0.12, 0)
	sauce.name = "Liquid"
	root.add_child(sauce)
	# Pepperoni
	for i in range(6):
		var ang := i * TAU / 6.0
		var pep := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.08
		pc.bottom_radius = 0.08
		pc.height = 0.025
		pep.mesh = pc
		pep.material_override = _break_mat(Color(0.65, 0.12, 0.10), 0.55)
		pep.position = Vector3(cos(ang) * 0.28, 0.15, sin(ang) * 0.28)
		pep.name = "Pep%d" % i
		root.add_child(pep)
	if is_instance_valid(_coffee_glow):
		_coffee_glow.light_color = Color(1.0, 0.6, 0.25)


func _break_build_cigarette(root: Node3D) -> void:
	## Cigarette plus réaliste : filtre orange, papier, tabac, braise + cendre + fumée.
	var tilt := 22.0
	root.rotation_degrees = Vector3(0, 0, -tilt)

	# Corps papier (blanc cassé, légèrement rugueux)
	var paper := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.038
	pc.bottom_radius = 0.038
	pc.height = 0.72
	pc.radial_segments = 24
	paper.mesh = pc
	var mat_paper := _break_mat(Color(0.96, 0.94, 0.90), 0.72)
	paper.material_override = mat_paper
	paper.position = Vector3(0, 0.52, 0)
	paper.name = "Paper"
	root.add_child(paper)

	# Ligne de colle / joint du papier (fin cylindre sombre décalé)
	var seam := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.039
	sc.bottom_radius = 0.039
	sc.height = 0.70
	sc.radial_segments = 8
	seam.mesh = sc
	var mat_seam := _break_mat(Color(0.88, 0.85, 0.80), 0.8)
	seam.material_override = mat_seam
	seam.scale = Vector3(0.15, 1.0, 1.0)
	seam.position = Vector3(0.032, 0.52, 0)
	root.add_child(seam)

	# Filtre (liège / orange classique)
	var filt := MeshInstance3D.new()
	var fc := CylinderMesh.new()
	fc.top_radius = 0.040
	fc.bottom_radius = 0.040
	fc.height = 0.22
	fc.radial_segments = 24
	filt.mesh = fc
	var mat_f := _break_mat(Color(0.86, 0.58, 0.22), 0.62)
	filt.material_override = mat_f
	filt.position = Vector3(0, 0.11, 0)
	root.add_child(filt)

	# Bande entre filtre et papier
	var band := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.041
	bc.bottom_radius = 0.041
	bc.height = 0.025
	band.mesh = bc
	band.material_override = _break_mat(Color(0.75, 0.48, 0.18), 0.55)
	band.position = Vector3(0, 0.23, 0)
	root.add_child(band)

	# Bout du filtre (extrémité)
	var fend := MeshInstance3D.new()
	var fe := CylinderMesh.new()
	fe.top_radius = 0.036
	fe.bottom_radius = 0.040
	fe.height = 0.02
	fend.mesh = fe
	fend.material_override = _break_mat(Color(0.92, 0.88, 0.78), 0.7)
	fend.position = Vector3(0, 0.01, 0)
	root.add_child(fend)

	# Zone tabac brûlée / cendre grise juste avant la braise
	var ash := MeshInstance3D.new()
	var ac := CylinderMesh.new()
	ac.top_radius = 0.037
	ac.bottom_radius = 0.038
	ac.height = 0.07
	ac.radial_segments = 16
	ash.mesh = ac
	ash.material_override = _break_mat(Color(0.35, 0.33, 0.30), 0.95)
	ash.position = Vector3(0, 0.90, 0)
	ash.name = "Ash"
	root.add_child(ash)

	# Braise (orange/rouge, émissive)
	var ember := MeshInstance3D.new()
	var ec := SphereMesh.new()
	ec.radius = 0.042
	ec.height = 0.07
	ec.radial_segments = 16
	ec.rings = 8
	ember.mesh = ec
	var mat_e := _break_mat(Color(0.55, 0.12, 0.04), 0.4, 0.0, Color(1.0, 0.35, 0.05), 2.8)
	ember.material_override = mat_e
	ember.position = Vector3(0, 0.96, 0)
	ember.name = "Liquid"
	root.add_child(ember)

	# Petit halo de braise
	var glow_tip := MeshInstance3D.new()
	var gs := SphereMesh.new()
	gs.radius = 0.055
	gs.height = 0.09
	glow_tip.mesh = gs
	var mat_g := _break_mat(Color(1.0, 0.4, 0.05, 0.35), 0.3, 0.0, Color(1.0, 0.45, 0.08), 1.5)
	mat_g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_tip.material_override = mat_g
	glow_tip.position = Vector3(0, 0.97, 0)
	root.add_child(glow_tip)

	_break_add_smoke(root, Vector3(0, 1.05, 0), Color(0.55, 0.55, 0.55, 0.55), 36)
	if is_instance_valid(_coffee_glow):
		_coffee_glow.position = Vector3(0.05, 1.0, 0.2)
		_coffee_glow.light_color = Color(1.0, 0.4, 0.12)
		_coffee_glow.light_energy = 1.3


func _break_build_marijuana(root: Node3D) -> void:
	## Joint / blunt plus réaliste : cône, papier brun, embout tordu, braise, fumée.
	var tilt := -14.0
	root.rotation_degrees = Vector3(0, 0, tilt)

	# Corps conique (papier brun)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.028   # côté braise (plus fin)
	cyl.bottom_radius = 0.055  # côté bouche (plus large)
	cyl.height = 0.88
	cyl.radial_segments = 20
	body.mesh = cyl
	var mat_paper := _break_mat(Color(0.62, 0.52, 0.32), 0.78)
	body.material_override = mat_paper
	body.position = Vector3(0, 0.48, 0)
	body.name = "Paper"
	root.add_child(body)

	# Veinures / plis du papier (fins anneaux)
	for i in range(4):
		var ring := MeshInstance3D.new()
		var rc := CylinderMesh.new()
		var t := float(i) / 3.0
		var r := lerpf(0.056, 0.030, t)
		rc.top_radius = r
		rc.bottom_radius = r
		rc.height = 0.012
		ring.mesh = rc
		ring.material_override = _break_mat(Color(0.50, 0.42, 0.26), 0.85)
		ring.position = Vector3(0, 0.12 + t * 0.72, 0)
		root.add_child(ring)

	# Embout tordu (bout bouche)
	var tip_mouth := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.05
	tm.height = 0.09
	tm.radial_segments = 12
	tip_mouth.mesh = tm
	tip_mouth.material_override = _break_mat(Color(0.48, 0.40, 0.24), 0.75)
	tip_mouth.scale = Vector3(1.0, 0.7, 1.0)
	tip_mouth.position = Vector3(0, 0.04, 0)
	root.add_child(tip_mouth)

	# Contenu visible au bord (vert/brun)
	var herb_edge := MeshInstance3D.new()
	var he := CylinderMesh.new()
	he.top_radius = 0.026
	he.bottom_radius = 0.027
	he.height = 0.04
	herb_edge.mesh = he
	herb_edge.material_override = _break_mat(Color(0.28, 0.42, 0.18), 0.9)
	herb_edge.position = Vector3(0, 0.90, 0)
	root.add_child(herb_edge)

	# Cendre
	var ash := MeshInstance3D.new()
	var ac := CylinderMesh.new()
	ac.top_radius = 0.024
	ac.bottom_radius = 0.027
	ac.height = 0.05
	ash.mesh = ac
	ash.material_override = _break_mat(Color(0.32, 0.30, 0.28), 0.95)
	ash.position = Vector3(0, 0.94, 0)
	ash.name = "Ash"
	root.add_child(ash)

	# Braise
	var ember := MeshInstance3D.new()
	var es := SphereMesh.new()
	es.radius = 0.032
	es.height = 0.055
	ember.mesh = es
	ember.material_override = _break_mat(Color(0.45, 0.15, 0.04), 0.45, 0.0, Color(1.0, 0.4, 0.08), 2.4)
	ember.position = Vector3(0, 0.99, 0)
	ember.name = "Liquid"
	root.add_child(ember)

	# Halo braise
	var halo := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.045
	halo.mesh = hs
	var mat_h := _break_mat(Color(1.0, 0.45, 0.08, 0.3), 0.3, 0.0, Color(1.0, 0.5, 0.1), 1.2)
	mat_h.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.material_override = mat_h
	halo.position = Vector3(0, 1.0, 0)
	root.add_child(halo)

	_break_add_smoke(root, Vector3(0, 1.08, 0), Color(0.58, 0.62, 0.52, 0.5), 42)
	if is_instance_valid(_coffee_glow):
		_coffee_glow.position = Vector3(0.0, 1.05, 0.15)
		_coffee_glow.light_color = Color(0.75, 0.9, 0.45)
		_coffee_glow.light_energy = 1.1


func _break_add_smoke(root: Node3D, pos: Vector3, col: Color, amount: int = 32) -> void:
	## Fumée plus lente et volumineuse que la vapeur de café.
	_coffee_steam = GPUParticles3D.new()
	_coffee_steam.position = pos
	_coffee_steam.amount = amount
	_coffee_steam.lifetime = 2.6
	_coffee_steam.explosiveness = 0.02
	_coffee_steam.randomness = 0.45
	_coffee_steam.visibility_aabb = AABB(Vector3(-1.2, -0.3, -1.2), Vector3(2.4, 3.0, 2.4))
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0.08, 1.0, 0.05)
	pmat.spread = 22.0
	pmat.initial_velocity_min = 0.08
	pmat.initial_velocity_max = 0.22
	pmat.gravity = Vector3(0, 0.06, 0)
	pmat.scale_min = 0.06
	pmat.scale_max = 0.16
	pmat.color = col
	pmat.damping_min = 0.4
	pmat.damping_max = 0.9
	_coffee_steam.process_material = pmat
	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = 0.55
	smoke_mesh.height = 1.1
	var smoke_draw := StandardMaterial3D.new()
	smoke_draw.albedo_color = Color(col.r, col.g, col.b, 0.28)
	smoke_draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_draw.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_coffee_steam.draw_pass_1 = smoke_mesh
	_coffee_steam.material_override = smoke_draw
	_coffee_steam.emitting = true
	root.add_child(_coffee_steam)


func _break_add_steam(root: Node3D, pos: Vector3, col: Color) -> void:
	_coffee_steam = GPUParticles3D.new()
	_coffee_steam.position = pos
	_coffee_steam.amount = 22
	_coffee_steam.lifetime = 1.8
	_coffee_steam.visibility_aabb = AABB(Vector3(-1, -0.2, -1), Vector3(2, 2.5, 2))
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 18.0
	pmat.initial_velocity_min = 0.15
	pmat.initial_velocity_max = 0.35
	pmat.gravity = Vector3(0, 0.15, 0)
	pmat.scale_min = 0.04
	pmat.scale_max = 0.10
	pmat.color = col
	_coffee_steam.process_material = pmat
	var steam_mesh := SphereMesh.new()
	steam_mesh.radius = 0.5
	steam_mesh.height = 1.0
	var steam_draw := StandardMaterial3D.new()
	steam_draw.albedo_color = Color(col.r, col.g, col.b, 0.35)
	steam_draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	steam_draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_coffee_steam.draw_pass_1 = steam_mesh
	_coffee_steam.material_override = steam_draw
	_coffee_steam.emitting = true
	root.add_child(_coffee_steam)


func _hide_coffee_break() -> void:
	if not _coffee_active and not is_instance_valid(_coffee_layer):
		return
	_coffee_active = false
	_break_warn_label = null
	_break_msg_label = null
	_break_phase = 0.0
	if is_instance_valid(_coffee_layer):
		var layer := _coffee_layer
		var t := create_tween()
		t.tween_property(layer, "modulate:a", 0.0, 0.25)
		t.tween_callback(func():
			if is_instance_valid(layer):
				layer.queue_free()
			if layer == _coffee_layer:
				_coffee_layer = null
		)
	_coffee_cup = null
	_coffee_steam = null
	_coffee_glow = null


var _media_sync_acc: float = 0.0


func _process(delta: float) -> void:
	if _crt_enabled:
		_crt_tick(delta)
	if _neon_enabled:
		_neon_tick(delta)
	if _predator_enabled:
		_predator_tick(delta)
	if _rain_enabled:
		_rain_tick(delta)
	if _paper_enabled:
		_paper_tick(delta)
	# Flush graffiti texture au plus ~20 fps
	if _tag_dirty:
		_tag_flush_acc += delta
		if _tag_flush_acc >= 0.05:
			_tag_flush_acc = 0.0
			_tag_dirty = false
			if _tag_texture != null and _tag_image != null:
				_tag_texture.update(_tag_image)
	# Lecteur audio : maj seek / temps
	_media_sync_acc += delta
	if _media_sync_acc >= 0.25:
		_media_sync_acc = 0.0
		if is_instance_valid(_music_player) and _music_player.stream != null:
			if _music_player.playing or _music_player.stream_paused:
				_music_sync_ui()
		# Lecteur vidéo
		if is_instance_valid(_video_player) and _video_player.is_playing() and not _video_seeking:
			_video_sync_ui()
	if not _coffee_active:
		return
	_break_phase = minf(_break_phase + delta * 0.12, 1.0)  # ~8s pour l'expérience complète
	_break_sip_t += delta
	_coffee_heat = _break_phase
	_break_animate_experience(delta)



func _break_animate_experience(delta: float) -> void:
	## Fait « vivre » la pause : boire, manger, fumer — progression + gestes rythmés.
	if not is_instance_valid(_coffee_cup):
		return
	var p := _break_phase
	var sip := sin(_break_sip_t * 2.2)  # -1..1 rythme gorgée / bouffée
	var sip01 := sip * 0.5 + 0.5

	# Message immersif selon la progression
	if is_instance_valid(_break_msg_label):
		var stage := 0
		if p > 0.75:
			stage = 3
		elif p > 0.45:
			stage = 2
		elif p > 0.18:
			stage = 1
		var key := "break_live_%s_%d" % [_break_kind, stage]
		var t := tr_ui(key)
		if t != key:
			_break_msg_label.text = t

	if is_instance_valid(_coffee_glow):
		_coffee_glow.light_energy = 0.65 + p * 0.7 + sip01 * 0.25

	match _break_kind:
		"coffee":
			_break_anim_drink(delta, p, sip, true)
		"cola":
			_break_anim_drink(delta, p, sip, false)
		"pizza":
			_break_anim_eat(delta, p, sip)
		"cigarette", "marijuana":
			_break_anim_smoke(delta, p, sip)
		_:
			_coffee_cup.rotate_y(delta * 0.5)


func _break_anim_drink(delta: float, p: float, sip: float, is_coffee: bool) -> void:
	## Inclinaison type « porter à la bouche », niveau qui baisse.
	var base_y := 0.02 * sin(Time.get_ticks_msec() * 0.0015)
	# Gorgée : pencher vers la caméra (axe X)
	var tilt := 8.0 + maxf(0.0, sip) * (28.0 if is_coffee else 22.0)
	# Vers la fin, presque vide → plus penché
	tilt += p * 12.0
	_coffee_cup.rotation_degrees = Vector3(tilt, _coffee_cup.rotation_degrees.y + delta * 25.0, sip * 4.0)
	_coffee_cup.position = Vector3(sip * 0.04, base_y + maxf(0.0, sip) * 0.08, -maxf(0.0, sip) * 0.12)

	var liq := _coffee_cup.get_node_or_null("Liquid") as MeshInstance3D
	if is_instance_valid(liq):
		# Niveau qui descend
		var lvl := clampf(1.0 - p * 0.92, 0.06, 1.0)
		liq.scale = Vector3(1.0, lvl, 1.0)
		liq.position.y = (0.48 if is_coffee else 0.12) * (0.55 + lvl * 0.45)
		if liq.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = liq.material_override
			m.emission_energy_multiplier = 0.25 + (1.0 - p) * 0.8

	if is_instance_valid(_coffee_steam):
		# Vapeur / bulles plus fortes au début de la gorgée
		var burst := 1.0 + maxf(0.0, sip) * 1.4
		_coffee_steam.amount = int((18 + (1.0 - p) * 22) * burst)
		var pm := _coffee_steam.process_material as ParticleProcessMaterial
		if pm:
			pm.initial_velocity_min = 0.10 + maxf(0.0, sip) * 0.15
			pm.initial_velocity_max = 0.25 + maxf(0.0, sip) * 0.25


func _break_anim_eat(delta: float, p: float, sip: float) -> void:
	## Pizza : parts qui disparaissent une à une, léger geste « mordre ».
	_coffee_cup.rotation_degrees = Vector3(
		5.0 + maxf(0.0, sip) * 10.0,
		_coffee_cup.rotation_degrees.y + delta * 18.0,
		sip * 6.0
	)
	_coffee_cup.position = Vector3(sip * 0.05, 0.02 + maxf(0.0, sip) * 0.06, -maxf(0.0, sip) * 0.1)

	var base := _coffee_cup.get_node_or_null("PizzaBase") as MeshInstance3D
	if is_instance_valid(base):
		# La base s’affine un peu (mangée)
		var s := clampf(1.0 - p * 0.35, 0.55, 1.0)
		base.scale = Vector3(s, 1.0, s)

	var sauce := _coffee_cup.get_node_or_null("Liquid") as MeshInstance3D
	if is_instance_valid(sauce):
		var s2 := clampf(1.0 - p * 0.5, 0.4, 1.0)
		sauce.scale = Vector3(s2, 1.0, s2)

	# Pepperoni : disparaissent dans l’ordre
	for i in range(6):
		var pep := _coffee_cup.get_node_or_null("Pep%d" % i) as MeshInstance3D
		if not is_instance_valid(pep):
			continue
		var threshold := float(i) / 6.0
		if p > threshold + 0.08:
			pep.visible = false
		else:
			pep.visible = true
			# juste avant de disparaître : rétrécit
			if p > threshold:
				var k := clampf(1.0 - (p - threshold) / 0.08, 0.0, 1.0)
				pep.scale = Vector3(k, k, k)
			else:
				pep.scale = Vector3.ONE


func _break_anim_smoke(delta: float, p: float, sip: float) -> void:
	## Cigarette / joint : se consume, cendre grossit, bouffées de fumée.
	var drag := maxf(0.0, sip)  # phase « inhale »
	# Gestuelle : rapprocher de la caméra pendant la bouffée
	_coffee_cup.position = Vector3(
		drag * 0.06,
		0.02 + drag * 0.05,
		-drag * 0.18
	)
	var base_tilt := -18.0 if _break_kind == "cigarette" else 12.0
	_coffee_cup.rotation_degrees = Vector3(
		base_tilt + drag * 15.0,
		_coffee_cup.rotation_degrees.y + delta * 12.0,
		drag * 5.0
	)

	# Corps / papier qui raccourcit (brûle)
	var paper := _coffee_cup.get_node_or_null("Paper") as MeshInstance3D
	if is_instance_valid(paper):
		var remain := clampf(1.0 - p * 0.75, 0.22, 1.0)
		paper.scale = Vector3(1.0, remain, 1.0)
		# garde le filtre en bas : pivot haut → décaler
		paper.position.y = 0.52 * remain + (0.52 - 0.52 * remain) * 0.15

	var ash := _coffee_cup.get_node_or_null("Ash") as MeshInstance3D
	if is_instance_valid(ash):
		var grow := 0.7 + p * 1.8
		ash.scale = Vector3(1.0 + p * 0.3, grow, 1.0 + p * 0.3)
		ash.position.y = 0.88 - p * 0.35

	var ember := _coffee_cup.get_node_or_null("Liquid") as MeshInstance3D
	if is_instance_valid(ember):
		ember.position.y = 0.96 - p * 0.4
		var pulse := 1.0 + drag * 0.8 + sin(_break_sip_t * 8.0) * 0.15
		if ember.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = ember.material_override
			m.emission_energy_multiplier = 1.5 * pulse + p * 0.5
		ember.scale = Vector3.ONE * (0.9 + drag * 0.25)

	if is_instance_valid(_coffee_steam):
		# Bouffée : plus de fumée quand on « tire »
		var amt := int(20 + p * 20 + drag * 40)
		_coffee_steam.amount = clampi(amt, 12, 64)
		var pm := _coffee_steam.process_material as ParticleProcessMaterial
		if pm:
			pm.initial_velocity_min = 0.12 + drag * 0.25
			pm.initial_velocity_max = 0.28 + drag * 0.4
			pm.spread = 18.0 + drag * 14.0



# ══════════════════════════════════════════════════════════════════════════════
# MUSIQUE CODING (lecteur avancé) + CITATION DU JOUR
# ══════════════════════════════════════════════════════════════════════════════

func _on_music_pick() -> void:
	if is_instance_valid(_music_file_dialog):
		_music_file_dialog.popup_centered_ratio(0.65)
	else:
		_feedback(tr_ui("music_fail"), "warn")


func _on_music_file_selected(path: String) -> void:
	_music_playlist_add([path], true)


func _on_music_files_selected(paths: PackedStringArray) -> void:
	var arr: Array = []
	for p in paths:
		arr.append(str(p))
	_music_playlist_add(arr, true)


func _music_update_label() -> void:
	if not is_instance_valid(_music_label):
		return
	if _music_path == "":
		_music_label.text = tr_ui("music_none")
		return
	_music_label.text = tr_ui("music_playing") % _music_path.get_file()


func _music_format_time(sec: float) -> String:
	if sec < 0.0 or not is_finite(sec):
		sec = 0.0
	var s := int(sec) % 60
	var m := int(sec) / 60
	return "%d:%02d" % [m, s]


func _music_sync_ui() -> void:
	_music_update_label()
	var playing := is_instance_valid(_music_player) and _music_player.playing and not _music_player.stream_paused
	var paused := is_instance_valid(_music_player) and _music_player.stream_paused
	var icon := tr_ui("music_play")
	if playing:
		icon = tr_ui("music_pause")
	elif paused:
		icon = tr_ui("music_play")
	if is_instance_valid(_music_play_btn):
		_music_play_btn.text = icon
	if has_meta("music_play2"):
		var p2 = get_meta("music_play2")
		if is_instance_valid(p2):
			p2.text = icon
	if is_instance_valid(_music_time_label):
		var cur := 0.0
		if is_instance_valid(_music_player) and _music_player.stream != null:
			cur = _music_player.get_playback_position()
		_music_time_label.text = tr_ui("music_time") % [_music_format_time(cur), _music_format_time(_music_duration)]
	if is_instance_valid(_music_seek) and not _music_seeking and _music_duration > 0.01:
		if is_instance_valid(_music_player):
			_music_seek.value = clampf(_music_player.get_playback_position() / _music_duration, 0.0, 1.0)


func _on_music_toggle() -> void:
	if not is_instance_valid(_music_player):
		return
	if _music_path == "":
		_on_music_pick()
		return
	if _music_player.stream == null:
		_music_load_and_play(true)
		return
	if _music_player.playing and not _music_player.stream_paused:
		_music_player.stream_paused = true
	elif _music_player.stream_paused:
		_music_player.stream_paused = false
	else:
		_music_player.play()
	_music_sync_ui()
	if not is_processing():
		set_process(true)


func _on_music_stop() -> void:
	if not is_instance_valid(_music_player):
		return
	_music_player.stop()
	_music_player.stream_paused = false
	if is_instance_valid(_music_seek):
		_music_seek.value = 0.0
	_music_sync_ui()


func _on_music_loop_toggled(on: bool) -> void:
	_music_loop = on
	_save_config()


func _on_music_volume_changed(v: float) -> void:
	_music_volume_db = v
	if is_instance_valid(_music_player) and not (is_instance_valid(_music_mute_check) and _music_mute_check.button_pressed):
		_music_player.volume_db = v
	_save_config()


func _on_music_mute_toggled(on: bool) -> void:
	if not is_instance_valid(_music_player):
		return
	_music_player.volume_db = -80.0 if on else _music_volume_db


func _on_music_rate_selected(idx: int) -> void:
	if not is_instance_valid(_music_rate) or not is_instance_valid(_music_player):
		return
	var rate := float(_music_rate.get_item_metadata(idx))
	_music_player.pitch_scale = rate


func _on_music_seek_ended(changed: bool) -> void:
	_music_seeking = false
	if not changed or not is_instance_valid(_music_player) or _music_player.stream == null:
		return
	if _music_duration <= 0.01:
		return
	var pos := _music_seek.value * _music_duration
	var was_playing := _music_player.playing and not _music_player.stream_paused
	_music_player.play(pos)
	if not was_playing:
		_music_player.stream_paused = true
	_music_sync_ui()


func _on_music_finished() -> void:
	# Boucle titre (1 piste ou option loop sur la piste courante)
	if _music_loop and _music_playlist.size() <= 1 and _music_path != "":
		_music_player.play(0.0)
		return
	if _music_loop and _music_playlist.size() <= 1:
		_music_sync_ui()
		return
	# Playlist : titre suivant
	if _music_playlist.size() > 0:
		var next_i := _music_pl_index + 1
		if next_i >= _music_playlist.size():
			if _music_loop:
				next_i = 0
			else:
				_music_sync_ui()
				return
		_music_play_index(next_i, true)
	else:
		_music_sync_ui()


func _music_load_and_play(autoplay: bool = true) -> void:
	if _music_path == "" or not is_instance_valid(_music_player):
		return
	if not FileAccess.file_exists(_music_path):
		_feedback(tr_ui("music_fail"), "warn")
		return
	var stream: AudioStream = null
	var ext := _music_path.get_extension().to_lower()
	if _music_path.begins_with("res://"):
		stream = load(_music_path) as AudioStream
	else:
		match ext:
			"ogg":
				stream = AudioStreamOggVorbis.load_from_file(_music_path)
			"mp3":
				var f := FileAccess.open(_music_path, FileAccess.READ)
				if f:
					var mp3 := AudioStreamMP3.new()
					mp3.data = f.get_buffer(f.get_length())
					stream = mp3
			"wav", "flac":
				stream = load(_music_path) as AudioStream
			_:
				stream = load(_music_path) as AudioStream
	if stream == null:
		_feedback(tr_ui("music_fail"), "warn")
		_log("Audio load failed: %s" % _music_path)
		return
	# Boucle gérée via signal finished (playlist / titre) — pas de loop natif stream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	_music_player.stream = stream
	_music_player.volume_db = -80.0 if (is_instance_valid(_music_mute_check) and _music_mute_check.button_pressed) else _music_volume_db
	if is_instance_valid(_music_rate):
		var idx := _music_rate.selected
		if idx >= 0:
			_music_player.pitch_scale = float(_music_rate.get_item_metadata(idx))
	_music_duration = 0.0
	if stream != null:
		_music_duration = maxf(0.0, float(stream.get_length()))
	if is_instance_valid(_music_seek):
		_music_seek.value = 0.0
	if autoplay:
		_music_player.stream_paused = false
		_music_player.play()
		if not is_processing():
			set_process(true)
	_music_update_label()
	_music_sync_ui()
	_log("♪ " + _music_path.get_file())


func _maybe_show_quote_of_the_day() -> void:
	## Une seule citation par jour civil (persistée).
	var day := Time.get_date_string_from_system()  # YYYY-MM-DD
	if _quote_shown_day == day:
		return
	_quote_shown_day = day
	_save_config()
	var bag: Array = _mascot_lang_bag(MASCOT_DEV_FR, MASCOT_DEV_EN, MASCOT_DEV_ZH)
	if bag.is_empty():
		return
	# Stable par jour : même citation toute la journée
	var idx := int(day.hash()) % bag.size()
	if idx < 0:
		idx = -idx
	var quote: String = bag[idx]
	var msg := "%s — %s" % [tr_ui("quote_prefix"), quote]
	_feedback(msg, "info")
	_log(msg, "info")



# ── Support tickets ─────────────────────────────────────────────────────────
func _support_fill_categories() -> void:
	if not is_instance_valid(support_category):
		return
	support_category.clear()
	var keys := [
		"plugin_deploy", "account", "payment", "payout", "moderation",
		"download", "content", "api", "feature", "other"
	]
	for k in keys:
		support_category.add_item(tr_ui("support_cat_%s" % k))
		support_category.set_item_metadata(support_category.item_count - 1, k)
	support_category.select(0)


func _support_selected_category() -> String:
	if not is_instance_valid(support_category) or support_category.selected < 0:
		return "other"
	var m = support_category.get_item_metadata(support_category.selected)
	return str(m) if m != null else "other"


func _on_support_submit() -> void:
	if access_token == "":
		_feedback(tr_ui("support_need_auth"), "warn")
		return
	var subject := support_subject_edit.text.strip_edges() if is_instance_valid(support_subject_edit) else ""
	var body := support_body_edit.text.strip_edges() if is_instance_valid(support_body_edit) else ""
	if subject.is_empty() or body.is_empty():
		_feedback(tr_ui("support_body_ph"), "warn")
		return
	var cat := _support_selected_category()
	var ctx_parts: PackedStringArray = []
	ctx_parts.append("plugin=thiossane_deploy")
	ctx_parts.append("godot=%s" % Engine.get_version_info().get("string", "?"))
	ctx_parts.append("os=%s" % OS.get_name())
	if selected_game_id > 0:
		ctx_parts.append("game_id=%d" % selected_game_id)
	var payload := {
		"category": cat,
		"subject": subject,
		"body": body,
		"source": "plugin",
		"priority": "normal",
		"context": " | ".join(ctx_parts),
	}
	if selected_game_id > 0:
		payload["game_id"] = selected_game_id
	_set_busy(true)
	_request_json(HTTPClient.METHOD_POST, "/support/tickets", payload, ReqKind.SUPPORT_CREATE)


func _handle_support_create(code: int, data: Variant) -> void:
	_set_busy(false)
	if code >= 200 and code < 300 and typeof(data) == TYPE_DICTIONARY:
		var tid: int = int(data.get("id", 0))
		_feedback(tr_ui("support_sent") % tid, "ok")
		_log("Support ticket #%d created" % tid, "ok")
		if is_instance_valid(support_subject_edit):
			support_subject_edit.text = ""
		if is_instance_valid(support_body_edit):
			support_body_edit.text = ""
		_on_support_refresh()
	else:
		_feedback(_api_error_message(data, code), "err")
		_log("Support create failed: %s" % _api_error_message(data, code), "err")


func _on_support_refresh() -> void:
	if access_token == "":
		_feedback(tr_ui("support_need_auth"), "warn")
		return
	_request_json(HTTPClient.METHOD_GET, "/support/tickets/mine", {}, ReqKind.SUPPORT_LIST)


func _handle_support_list(code: int, data: Variant) -> void:
	if code < 200 or code >= 300:
		_log("Support list HTTP %d" % code, "err")
		return
	_support_tickets = data if typeof(data) == TYPE_ARRAY else []
	if not is_instance_valid(support_list):
		return
	support_list.clear()
	if _support_tickets.is_empty():
		support_list.add_item(tr_ui("support_empty"))
		support_list.set_item_disabled(0, true)
		return
	for t in _support_tickets:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var id: int = int(t.get("id", 0))
		var st: String = str(t.get("status", ""))
		var sub: String = str(t.get("subject", ""))
		var cat: String = str(t.get("category_label", t.get("category", "")))
		support_list.add_item("#%d [%s] %s — %s" % [id, st, cat, sub])
		support_list.set_item_metadata(support_list.item_count - 1, id)


func _on_support_ticket_selected(idx: int) -> void:
	if not is_instance_valid(support_list) or idx < 0:
		return
	var mid = support_list.get_item_metadata(idx)
	if mid == null:
		return
	_support_selected_id = int(mid)
	_request_json(HTTPClient.METHOD_GET, "/support/tickets/%d" % _support_selected_id, {}, ReqKind.SUPPORT_GET)


func _handle_support_get(code: int, data: Variant) -> void:
	if code < 200 or code >= 300 or typeof(data) != TYPE_DICTIONARY:
		_feedback(_api_error_message(data, code), "err")
		return
	var lines: PackedStringArray = []
	lines.append("#%d — %s [%s]" % [int(data.get("id", 0)), str(data.get("subject", "")), str(data.get("status", ""))])
	var msgs = data.get("messages", [])
	if typeof(msgs) == TYPE_ARRAY:
		for m in msgs:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var who := "Staff" if bool(m.get("is_staff", false)) else "Vous"
			lines.append("[%s] %s: %s" % [str(m.get("created_at", "")), who, str(m.get("body", ""))])
	if is_instance_valid(support_detail_label):
		support_detail_label.text = "\n".join(lines)
		support_detail_label.modulate = Color.WHITE


func _on_support_reply() -> void:
	if access_token == "" or _support_selected_id <= 0:
		_feedback(tr_ui("support_select"), "warn")
		return
	var body := support_reply_edit.text.strip_edges() if is_instance_valid(support_reply_edit) else ""
	if body.is_empty():
		return
	_request_json(HTTPClient.METHOD_POST, "/support/tickets/%d/reply" % _support_selected_id, {"body": body}, ReqKind.SUPPORT_REPLY)


func _handle_support_reply(code: int, data: Variant) -> void:
	if code >= 200 and code < 300:
		if is_instance_valid(support_reply_edit):
			support_reply_edit.text = ""
		_feedback("OK", "ok")
		_request_json(HTTPClient.METHOD_GET, "/support/tickets/%d" % _support_selected_id, {}, ReqKind.SUPPORT_GET)
		_on_support_refresh()
	else:
		_feedback(_api_error_message(data, code), "err")


# ── Notifications in-app (badges sur sections) ───────────────────────────────

func _attach_section_badges() -> void:
	## Place une boule (badge) sur chaque section pouvant recevoir une notif.
	_section_badges.clear()
	var map := {
		"conn": _sec_conn,
		"game": _sec_game,
		"fiche": _sec_fiche,
		"plat": _sec_plat,
		"deploy": _sec_deploy,
		"share": _sec_share,
		"support": _sec_support,
		"prog": _sec_prog,
	}
	for key in map:
		var sec: Control = map[key]
		if not is_instance_valid(sec) or not sec.has_meta("header_row"):
			continue
		var head_row: HBoxContainer = sec.get_meta("header_row")
		if not is_instance_valid(head_row):
			continue
		var badge := Panel.new()
		badge.custom_minimum_size = Vector2(12, 12)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_STOP
		badge.visible = false
		badge.tooltip_text = ""
		_style_notif_badge(badge)
		# Clic gauche → lire ; clic droit → marquer lu sans alerte (rythme humain)
		var sec_key := str(key)
		badge.gui_input.connect(func(ev: InputEvent) -> void:
			if not (ev is InputEventMouseButton and ev.pressed):
				return
			if ev.button_index == MOUSE_BUTTON_LEFT:
				if ev.ctrl_pressed or ev.meta_pressed:
					_on_notif_mark_all_quiet()
				else:
					_on_section_badge_clicked(sec_key)
			elif ev.button_index == MOUSE_BUTTON_RIGHT:
				_consume_section_notifs(sec_key, false)
		)
		head_row.add_child(badge)
		# Marge droite pour ne pas coller au bord
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(10, 0)
		head_row.add_child(spacer)
		_section_badges[key] = badge
		# Ouvrir la section consomme aussi les notifs de cette section
		if sec.has_meta("header_btn"):
			var hb: Button = sec.get_meta("header_btn")
			if is_instance_valid(hb) and not hb.has_meta("notif_toggle_hooked"):
				hb.set_meta("notif_toggle_hooked", true)
				hb.toggled.connect(_on_section_toggled_for_notif.bind(sec_key))


func _style_notif_badge(badge: Panel) -> void:
	if not is_instance_valid(badge):
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_ERR
	sb.set_corner_radius_all(8)
	sb.anti_aliasing = true
	# Légère bordure pour rester lisible sur tous les thèmes
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(C_ERR.r * 0.6, C_ERR.g * 0.6, C_ERR.b * 0.6, 0.9)
	badge.add_theme_stylebox_override("panel", sb)


func _restyle_section_badges() -> void:
	for key in _section_badges:
		var badge: Panel = _section_badges[key]
		if is_instance_valid(badge):
			_style_notif_badge(badge)


func _notif_section_for(n: Dictionary) -> String:
	## Types backend (Notification::TYPE_*) → section dock.
	var t := str(n.get("type", "")).to_lower().strip_edges()
	match t:
		"support_reply", "support_status":
			return "support"
		"game_approved", "game_rejected", "game_needs_changes", "moderation":
			return "deploy"
		"payment":
			return "share"
		"account":
			return "conn"
		"report_update", "system":
			return "prog"
	# Fallback mots-clés (titre / body / data)
	var title := str(n.get("title", "")).to_lower()
	var body := str(n.get("body", "")).to_lower()
	var blob := "%s %s %s" % [t, title, body]
	if "support" in blob or "ticket" in blob:
		return "support"
	if "modér" in blob or "moder" in blob or "approuv" in blob or "rejet" in blob or "deploy" in blob:
		return "deploy"
	if "paiement" in blob or "payment" in blob or "versement" in blob or "payout" in blob or "vente" in blob:
		return "share"
	if "compte" in blob or "session" in blob or "account" in blob:
		return "conn"
	return "support"


func _recompute_notif_badges() -> void:
	var prev := _notif_prev_by_section.duplicate()
	_notif_by_section.clear()
	_notif_unread = 0
	for n in _notifications:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		if bool(n.get("is_read", true)):
			continue
		_notif_unread += 1
		var sec_key := _notif_section_for(n)
		_notif_by_section[sec_key] = int(_notif_by_section.get(sec_key, 0)) + 1
	for key in _section_badges:
		var badge: Panel = _section_badges[key]
		if not is_instance_valid(badge):
			continue
		var count: int = int(_notif_by_section.get(key, 0))
		badge.visible = count > 0
		if count > 0:
			badge.tooltip_text = tr_ui("notif_badge_tip") % count
		else:
			badge.tooltip_text = ""
	# Ouvrir auto la section concernée seulement si le compte a augmenté
	var sec_map := {
		"conn": _sec_conn, "game": _sec_game, "fiche": _sec_fiche, "plat": _sec_plat,
		"deploy": _sec_deploy, "share": _sec_share, "support": _sec_support, "prog": _sec_prog,
	}
	for key in _notif_by_section:
		var now_c: int = int(_notif_by_section[key])
		var was_c: int = int(prev.get(key, 0))
		if now_c > was_c and sec_map.has(key):
			_ensure_section_open(sec_map[key])
	_notif_prev_by_section = _notif_by_section.duplicate()


func _on_section_toggled_for_notif(open: bool, sec_key: String) -> void:
	## Signal Button.toggled(pressed: bool) ; sec_key vient de .bind() (après les args du signal).
	if open:
		_consume_section_notifs(sec_key, false)


func _on_section_badge_clicked(sec_key: String) -> void:
	_consume_section_notifs(sec_key, true)


func _consume_section_notifs(sec_key: String, show_feedback: bool) -> void:
	## Marque comme lues les notifs de la section et affiche éventuellement le dernier message.
	var last_title := ""
	var last_body := ""
	var any := false
	for n in _notifications:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		if bool(n.get("is_read", true)):
			continue
		if _notif_section_for(n) != sec_key:
			continue
		any = true
		var nid := int(n.get("id", 0))
		if nid > 0:
			_request_json(HTTPClient.METHOD_POST, "/notifications/%d/read" % nid, {}, ReqKind.GENERIC)
		n["is_read"] = true
		last_title = str(n.get("title", ""))
		last_body = str(n.get("body", ""))
	if any:
		_recompute_notif_badges()
		if show_feedback:
			if last_body != "":
				_feedback("%s — %s" % [last_title, last_body], "ok")
			elif last_title != "":
				_feedback(last_title, "ok")


func _on_notif_refresh() -> void:
	if access_token == "":
		return
	# Ne pas interrompre login / catégories / jeux (un seul HTTPRequest)
	if is_busy and _pending_kind in [ReqKind.LOGIN, ReqKind.ME, ReqKind.CATEGORIES, ReqKind.MY_GAMES, ReqKind.REFRESH]:
		return
	if _pending_kind in [ReqKind.LOGIN, ReqKind.ME, ReqKind.CATEGORIES, ReqKind.MY_GAMES, ReqKind.UPLOAD_INIT, ReqKind.UPLOAD_STATUS, ReqKind.UPLOAD_COMPLETE]:
		return
	_request_json(HTTPClient.METHOD_GET, "/notifications?limit=30", {}, ReqKind.NOTIF_LIST)


func _handle_notif_list(code: int, data: Variant) -> void:
	if code < 200 or code >= 300:
		return
	_notifications = []
	if typeof(data) == TYPE_DICTIONARY:
		var d: Dictionary = data
		var items = d.get("items", [])
		if typeof(items) == TYPE_ARRAY:
			_notifications = items
	_recompute_notif_badges()
	# Démarrer le poll une fois connecté
	if is_instance_valid(_notif_poll_timer) and _notif_poll_timer.is_stopped() and access_token != "":
		_notif_poll_timer.start()


func _handle_notif_mark_all(code: int, data: Variant) -> void:
	if code >= 200 and code < 300:
		for n in _notifications:
			if typeof(n) == TYPE_DICTIONARY:
				n["is_read"] = true
		_notif_prev_by_section.clear()
		_recompute_notif_badges()
	else:
		_feedback(_api_error_message(data, code), "err")




func _music_playlist_add(paths: Array, play_first_new: bool = false) -> void:
	var added := 0
	var first_new := -1
	for p in paths:
		var path := str(p)
		if path == "" or not FileAccess.file_exists(path):
			continue
		if path in _music_playlist:
			continue
		_music_playlist.append(path)
		if first_new < 0:
			first_new = _music_playlist.size() - 1
		added += 1
	if added == 0:
		_feedback(tr_ui("music_pl_empty_add"), "warn")
		return
	_music_playlist_refresh_ui()
	_save_config()
	_log(tr_ui("music_pl_added") % added, "ok")
	if play_first_new and first_new >= 0:
		_music_play_index(first_new, true)


func _music_playlist_refresh_ui() -> void:
	if not is_instance_valid(_music_playlist_list):
		return
	_music_playlist_list.clear()
	for i in range(_music_playlist.size()):
		var path: String = str(_music_playlist[i])
		var label := "%d. %s" % [i + 1, path.get_file()]
		_music_playlist_list.add_item(label)
		_music_playlist_list.set_item_metadata(i, path)
		if i == _music_pl_index:
			_music_playlist_list.select(i)
			_music_playlist_list.set_item_custom_fg_color(i, C_SECTION)
	if is_instance_valid(_music_pl_label):
		var n := _music_playlist.size()
		if n == 0:
			_music_pl_label.text = tr_ui("music_playlist")
		else:
			_music_pl_label.text = tr_ui("music_playlist_count") % [n, maxi(_music_pl_index + 1, 0)]


func _music_play_index(idx: int, autoplay: bool = true) -> void:
	if idx < 0 or idx >= _music_playlist.size():
		return
	_music_pl_index = idx
	_music_path = str(_music_playlist[idx])
	_music_playlist_refresh_ui()
	_save_config()
	_music_load_and_play(autoplay)


func _on_music_playlist_activated(idx: int) -> void:
	_music_play_index(idx, true)


func _on_music_playlist_selected(idx: int) -> void:
	# sélection visuelle seulement (lecture au double-clic / Entrée)
	pass


func _on_music_playlist_remove() -> void:
	if not is_instance_valid(_music_playlist_list):
		return
	var sel := _music_playlist_list.get_selected_items()
	if sel.is_empty():
		_feedback(tr_ui("music_pl_select_first"), "warn")
		return
	var idx: int = sel[0]
	if idx < 0 or idx >= _music_playlist.size():
		return
	_music_playlist.remove_at(idx)
	if _music_playlist.is_empty():
		_music_pl_index = -1
		_music_path = ""
		if is_instance_valid(_music_player):
			_music_player.stop()
			_music_player.stream = null
	else:
		if _music_pl_index >= _music_playlist.size():
			_music_pl_index = _music_playlist.size() - 1
		elif idx < _music_pl_index:
			_music_pl_index -= 1
		elif idx == _music_pl_index:
			_music_path = str(_music_playlist[_music_pl_index])
	_music_playlist_refresh_ui()
	_music_update_label()
	_music_sync_ui()
	_save_config()


func _on_music_playlist_clear() -> void:
	_music_playlist.clear()
	_music_pl_index = -1
	_music_path = ""
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null
	_music_playlist_refresh_ui()
	_music_update_label()
	_music_sync_ui()
	_save_config()
	_log(tr_ui("music_pl_cleared"), "info")


func _on_music_prev() -> void:
	if _music_playlist.is_empty():
		_feedback(tr_ui("music_pl_empty"), "warn")
		return
	var i := _music_pl_index - 1
	if i < 0:
		i = _music_playlist.size() - 1 if _music_loop else 0
	_music_play_index(i, true)


func _on_music_next() -> void:
	if _music_playlist.is_empty():
		_feedback(tr_ui("music_pl_empty"), "warn")
		return
	var i := _music_pl_index + 1
	if i >= _music_playlist.size():
		i = 0 if _music_loop else _music_playlist.size() - 1
	_music_play_index(i, true)


# ══════════════════════════════════════════════════════════════════════════════
# LECTEUR VIDÉO (section Avancé — wellbeing)
# ══════════════════════════════════════════════════════════════════════════════

func _on_video_pick() -> void:
	if is_instance_valid(_video_file_dialog):
		_video_file_dialog.popup_file_dialog()


func _on_video_file_selected(path: String) -> void:
	_video_path = path
	_video_load_and_play(true)


func _video_format_time(sec: float) -> String:
	var s := int(maxf(0.0, sec))
	return "%d:%02d" % [s / 60, s % 60]


func _video_sync_ui() -> void:
	if not is_instance_valid(_video_player):
		return
	var playing := _video_player.is_playing()
	if is_instance_valid(_video_play_btn):
		_video_play_btn.text = tr_ui("video_pause") if playing else tr_ui("video_play")
	var dur := 0.0
	if _video_player.get_stream_length() > 0.0:
		dur = _video_player.get_stream_length()
	var pos := _video_player.stream_position
	if is_instance_valid(_video_time_label):
		_video_time_label.text = tr_ui("video_time") % [_video_format_time(pos), _video_format_time(dur)]
	if is_instance_valid(_video_seek) and not _video_seeking and dur > 0.0:
		_video_seek.max_value = dur
		_video_seek.value = pos
	if is_instance_valid(_video_label):
		if _video_path == "":
			_video_label.text = tr_ui("video_none")
		else:
			_video_label.text = tr_ui("video_playing") if playing else _video_path.get_file()


func _on_video_toggle() -> void:
	if not is_instance_valid(_video_player):
		return
	if _video_path == "":
		_on_video_pick()
		return
	if _video_player.stream == null:
		_video_load_and_play(true)
		return
	if _video_player.is_playing():
		_video_player.paused = true
	else:
		_video_player.paused = false
		if not _video_player.is_playing():
			_video_player.play()
		if not is_processing():
			set_process(true)
	_video_sync_ui()


func _on_video_stop() -> void:
	if not is_instance_valid(_video_player):
		return
	_video_player.stop()
	_video_player.stream_position = 0.0
	if is_instance_valid(_video_seek):
		_video_seek.value = 0.0
	_video_sync_ui()


func _on_video_loop_toggled(on: bool) -> void:
	_video_loop = on


func _on_video_volume_changed(v: float) -> void:
	_video_volume = v
	if is_instance_valid(_video_player):
		_video_player.volume_db = linear_to_db(clampf(v, 0.0001, 1.0)) if v > 0.0 else -80.0


func _on_video_seek_ended(changed: bool) -> void:
	_video_seeking = false
	if not changed or not is_instance_valid(_video_player):
		return
	_video_player.stream_position = _video_seek.value


func _on_video_finished() -> void:
	if _video_loop and _video_path != "":
		_video_player.play()
	else:
		_video_sync_ui()


func _on_video_open_os() -> void:
	## Ouvre le fichier (ou un sélecteur) dans le lecteur système — utile pour MP4/WebM.
	if _video_path != "" and FileAccess.file_exists(_video_path):
		OS.shell_open(_video_path)
		_log(tr_ui("video_os_opened"), "info")
		return
	_on_video_pick()


func _video_load_and_play(autoplay: bool = true) -> void:
	if _video_path == "" or not FileAccess.file_exists(_video_path):
		_feedback(tr_ui("video_fail"), "err")
		return
	var ext := _video_path.get_extension().to_lower()
	# Godot embarque surtout Ogg Theora (.ogv). Les autres formats → lecteur OS.
	if ext != "ogv" and ext != "ogg":
		_log(tr_ui("video_format_os") % ext, "warn")
		_feedback(tr_ui("video_format_os") % ext, "warn")
		if is_instance_valid(_video_label):
			_video_label.text = _video_path.get_file()
		return
	var stream: VideoStream = null
	# VideoStreamTheora pour .ogv
	if ext == "ogv" or ext == "ogg":
		var theora := VideoStreamTheora.new()
		theora.file = _video_path
		stream = theora
	if stream == null:
		_feedback(tr_ui("video_fail"), "err")
		return
	_video_player.stop()
	_video_player.stream = stream
	_video_player.volume_db = linear_to_db(clampf(_video_volume, 0.0001, 1.0)) if _video_volume > 0.0 else -80.0
	if is_instance_valid(_video_seek):
		_video_seek.value = 0.0
	if autoplay:
		_video_player.paused = false
		_video_player.play()
		if not is_processing():
			set_process(true)
	_video_update_label()
	_video_sync_ui()
	_log("🎬 " + _video_path.get_file(), "ok")


func _video_update_label() -> void:
	if is_instance_valid(_video_label):
		if _video_path == "":
			_video_label.text = tr_ui("video_none")
		else:
			_video_label.text = _video_path.get_file()

