class_name ThiossaneStyles
extends RefCounted
## Helpers de style UI — palette passée en Dictionary pour rester indépendant du thème actif.
## Clés attendues : primary, primary_fg, accent, surface, card, border, muted, text,
##                  hover, pressed, ok, err (toutes Color).

static func card_style(p: Dictionary) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var c: Color = p.get("card", Color(0.10, 0.03, 0.05))
	sb.bg_color = Color(c.r, c.g, c.b, 0.94)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = p.get("border", Color(0.42, 0.12, 0.18))
	sb.shadow_color = Color(0, 0, 0, 0.22)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 2)
	sb.anti_aliasing = true
	return sb


static func primary_button(btn: Button, p: Dictionary, font_size: int = 14) -> void:
	if not is_instance_valid(btn):
		return
	btn.custom_minimum_size.y = 48
	btn.add_theme_font_size_override("font_size", font_size)
	var primary: Color = p.get("primary", Color(0.86, 0.14, 0.22))
	var primary_fg: Color = p.get("primary_fg", Color(0.98, 0.95, 0.94))
	var muted: Color = p.get("muted", Color(0.68, 0.48, 0.52))
	var normal := StyleBoxFlat.new()
	normal.bg_color = primary
	normal.set_corner_radius_all(11)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	normal.shadow_color = Color(primary.r, primary.g, primary.b, 0.35)
	normal.shadow_size = 8
	normal.shadow_offset = Vector2(0, 3)
	normal.anti_aliasing = true
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = primary.lightened(0.08)
	hover.shadow_size = 12
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = primary.darkened(0.12)
	pressed.shadow_size = 2
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = muted
	disabled.shadow_size = 0
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_color", primary_fg)
	btn.add_theme_color_override("font_hover_color", primary_fg)
	btn.add_theme_color_override("font_pressed_color", primary_fg.darkened(0.1))
	btn.add_theme_color_override("font_disabled_color", muted)


static func secondary_button(btn: Button, p: Dictionary, font_size: int = 14) -> void:
	if not is_instance_valid(btn):
		return
	btn.add_theme_font_size_override("font_size", font_size)
	btn.custom_minimum_size.y = 42
	var surface: Color = p.get("surface", Color(0.14, 0.05, 0.07))
	var border: Color = p.get("border", Color(0.42, 0.12, 0.18))
	var primary: Color = p.get("primary", Color(0.86, 0.14, 0.22))
	var text: Color = p.get("text", Color(0.98, 0.94, 0.92))
	var hover_c: Color = p.get("hover", Color(0.20, 0.07, 0.10))
	var pressed_c: Color = p.get("pressed", Color(0.08, 0.02, 0.04))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(surface.r, surface.g, surface.b, 0.92)
	normal.set_corner_radius_all(11)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.border_color = border
	normal.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	normal.shadow_size = 3
	normal.shadow_offset = Vector2(0, 1)
	normal.anti_aliasing = true
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = hover_c
	hover.border_color = primary
	hover.shadow_color = Color(primary.r, primary.g, primary.b, 0.28)
	hover.shadow_size = 6
	hover.shadow_offset = Vector2(0, 2)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = pressed_c
	pressed.border_color = primary.darkened(0.15)
	pressed.shadow_size = 1
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", text)
	btn.add_theme_color_override("font_hover_color", primary)
	btn.add_theme_color_override("font_pressed_color", primary.lightened(0.15))


static func success_button(btn: Button, p: Dictionary, font_size: int = 14) -> void:
	if not is_instance_valid(btn):
		return
	var ok: Color = p.get("ok", Color(0.169, 0.714, 0.451))
	var palette := p.duplicate()
	palette["primary"] = ok
	palette["primary_fg"] = Color(0.05, 0.12, 0.08)
	primary_button(btn, palette, font_size)


static func field_style(p: Dictionary, focused: bool = false, readonly: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var surface: Color = p.get("surface", Color(0.14, 0.05, 0.07))
	var primary: Color = p.get("primary", Color(0.86, 0.14, 0.22))
	var border: Color = p.get("border", Color(0.42, 0.12, 0.18))
	sb.bg_color = Color(0.08, 0.03, 0.04, 0.96) if readonly else surface
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = primary if focused else border
	sb.anti_aliasing = true
	return sb
