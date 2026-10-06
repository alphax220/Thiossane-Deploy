class_name ThiossaneConstants
extends RefCounted
## Constantes partagées — Thiossane Deploy

const CONFIG_SECTION := "thiossane_deploy"
const CONFIG_PATH := "user://thiossane_deploy.cfg"
const SECURE_TOKEN_PATH := "user://thiossane_tokens.dat"
const MAX_BUILD_BYTES := 512 * 1024 * 1024  # 512 Mo
const MAX_BUILD_MB := 512
const UPLOAD_CHUNK_SIZE := 2 * 1024 * 1024  # 2 Mo
const MAX_UPLOAD_WARN_MB := 200.0

# Couleurs par défaut (thème default)
const C_OK := Color(0.35, 0.78, 0.47)
const C_ERR := Color(0.91, 0.33, 0.33)
const C_WARN := Color(0.910, 0.725, 0.290)
const C_INFO := Color(0.910, 0.725, 0.290)
const C_MUTED := Color(0.58, 0.60, 0.64)
const C_IDLE := Color(0.58, 0.60, 0.64)
const C_BUSY := Color(0.910, 0.725, 0.290)
const C_BANNER_OK := Color(0.10, 0.22, 0.16, 0.95)
const C_BANNER_ERR := Color(0.28, 0.12, 0.12, 0.95)
const C_BANNER_WARN := Color(0.26, 0.22, 0.10, 0.95)
const C_BANNER_INFO := Color(0.16, 0.17, 0.20, 0.95)
const C_BANNER_IDLE := Color(0.12, 0.13, 0.15, 0.92)
const C_SECTION := Color(0.910, 0.725, 0.290)
const C_TEXT := Color(0.953, 0.925, 0.878)
const C_HOVER_SURFACE := Color(0.24, 0.25, 0.29)
const C_PRESSED_SURFACE := Color(0.14, 0.15, 0.18)
