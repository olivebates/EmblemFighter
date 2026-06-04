extends Node

# --- Menu palette (low → high importance) ---
# 0: darkest background
# 1–4: stepped gradient
# 5: text only
const MENU_0 := Color8(26, 17, 12)      # #1a110c
const MENU_1 := Color8(61, 42, 31)      # #3d2a1f
const MENU_2 := Color8(92, 64, 48)      # #5c4030
const MENU_3 := Color8(138, 99, 73)     # #8a6349
const MENU_4 := Color8(184, 146, 110)  # #b8926e
const MENU_TEXT := Color8(237, 224, 212) # #ede0d4 (text only)

# --- Panel chrome (bg N → border N+1) ---
const PANEL_BG_DARK := Color8(26, 17, 12, 255)          # MENU_0 (darkest)
const PANEL_BORDER_DARK := Color8(61, 42, 31, 220)      # MENU_1

const PANEL_BG := Color8(61, 42, 31, 245)               # MENU_1 (raised)
const PANEL_BORDER := Color8(92, 64, 48, 220)            # MENU_2

const PANEL_BORDER_ACCENT := Color8(138, 99, 73, 235)   # MENU_3
const PANEL_RADIUS := 6
const PANEL_RADIUS_SM := 4

# --- Button chrome (bg +1 from panel bg, hover +2; border +1 above bg) ---
const BTN_BG := Color8(61, 42, 31, 255)                 # MENU_1
const BTN_BORDER := Color8(92, 64, 48, 220)              # MENU_2
const BTN_BG_HOVER := Color8(92, 64, 48, 255)            # MENU_2
const BTN_BORDER_HOVER := Color8(138, 99, 73, 235)       # MENU_3

# --- Typography ---
const FONT_XS := 8
const FONT_SM := 10
const FONT_MD := 12
const FONT_LG := 16
const FONT_XL := 20
const FONT_DAMAGE := 22

const TEXT_PRIMARY := MENU_TEXT
const TEXT_MUTED := MENU_3
const TEXT_SUBTLE := MENU_4

# --- Faction tints (gameplay) ---
const HERO_ACCENT := Color(0.32, 0.92, 0.66)
const ENEMY_ACCENT := Color(1.0, 0.46, 0.4)
const MILESTONE := MENU_3

# --- Tile highlights (lower alpha) ---
const COLOR_MOVE := Color(0.2, 0.82, 0.42, 0.22)
const COLOR_MOVE_COVER := Color(0.78, 0.58, 0.12, 0.26)
const COLOR_SKILL_RANGE := Color(0.9, 0.2, 0.2, 0.20)
const COLOR_VALID_TARGET := Color(1.0, 0.85, 0.0, 0.85)
const COLOR_KILL_TARGET := Color(1.0, 0.15, 0.15, 0.55)
const COLOR_SKILL_PREVIEW := Color(0.3, 0.5, 1.0, 0.14)
const COLOR_TELEGRAPH_MOVE := Color(0.85, 0.25, 0.25, 0.28)
const COLOR_TELEGRAPH_TARGET := Color(1.0, 0.2, 0.2, 0.45)
const COLOR_COUNTER_EDGE := Color(0.25, 0.95, 0.45, 0.75)
const COLOR_HOVER_OUTLINE := Color(1.0, 1.0, 1.0, 0.7)

# --- Smart-cast paths ---
const COLOR_MOVE_PATH := Color(0.3, 0.82, 1.0, 0.85)
const COLOR_MOVE_DEST := Color(0.2, 0.65, 1.0, 0.35)

# --- Badge chips ---
const COLOR_CHIP_ADV := Color(0.38, 0.95, 0.48)
const COLOR_CHIP_WEAK := Color(0.95, 0.38, 0.38)
const COLOR_CHIP_MITIGATE := Color(0.58, 0.62, 0.72)
const COLOR_CHIP_POWER := Color(0.72, 0.74, 0.82)
const COLOR_DAMAGE_NORMAL := Color(0.94, 0.91, 0.86)
const COLOR_DAMAGE_KILL := Color(1.0, 0.42, 0.32)
const COLOR_HEAL := Color(0.35, 0.95, 0.52)
const COLOR_HEADER_WILL_USE := Color(0.28, 0.48, 0.82)

# --- Terrain (no sprite imports) ---
const TERRAIN_OBSTACLE := Color(0.28, 0.18, 0.10, 0.90)
const TERRAIN_COVER := Color(0.42, 0.32, 0.14, 0.72)
const GRID_LINE := Color(1.0, 1.0, 1.0, 0.06)


func panel_style(bg: Color = PANEL_BG, border: Color = PANEL_BORDER,
		radius: int = PANEL_RADIUS, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style


func tinted_panel_style(tint: Color, active: bool = false) -> StyleBoxFlat:
	var style := panel_style(PANEL_BG_DARK, tint * Color(0.45, 0.45, 0.45, 0.7), PANEL_RADIUS_SM,
			3 if active else 1)
	if active:
		style.border_color = tint.lightened(0.35)
	return style


func badge_panel_style(tint: Color) -> StyleBoxFlat:
	var style := panel_style(PANEL_BG_DARK, tint.lightened(0.18), PANEL_RADIUS, 2)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 2)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 0
	style.content_margin_bottom = 8
	return style


func badge_header_style(tint: Color, header: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if header == "WILL USE":
		style.bg_color = COLOR_HEADER_WILL_USE
	else:
		style.bg_color = Color(tint.r * 0.32, tint.g * 0.32, tint.b * 0.32, 0.95)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	style.content_margin_left = 6
	style.content_margin_right = 6
	return style


func chip_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.18)
	style.border_color = Color(color.r, color.g, color.b, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style


func apply_font(label: Label, size: int, color: Color = TEXT_PRIMARY) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.modulate = color


func apply_button_theme(btn: Button, active: bool = false, radius: int = PANEL_RADIUS_SM) -> void:
	var normal_bg := BTN_BG_HOVER if active else BTN_BG
	var normal_border := BTN_BORDER_HOVER if active else BTN_BORDER
	btn.add_theme_stylebox_override("normal",
			panel_style(normal_bg, normal_border, radius, 2 if active else 1))
	btn.add_theme_stylebox_override("hover",
			panel_style(BTN_BG_HOVER, BTN_BORDER_HOVER, radius, 2))
	btn.add_theme_stylebox_override("pressed",
			panel_style(BTN_BG, BTN_BORDER, radius, 2))
	btn.add_theme_stylebox_override("disabled",
			panel_style(PANEL_BG_DARK, PANEL_BORDER_DARK, radius, 1))
	btn.add_theme_stylebox_override("focus",
			panel_style(BTN_BG_HOVER, BTN_BORDER_HOVER, radius, 2))
	btn.add_theme_color_override("font_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_pressed_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_focus_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_disabled_color", TEXT_MUTED)


func apply_prominent_button_theme(btn: Button, radius: int = PANEL_RADIUS_SM) -> void:
	var normal_bg := Color8(92, 64, 48, 255)
	var hover_bg := Color8(138, 99, 73, 255)
	var pressed_bg := Color8(26, 17, 12, 255)
	btn.add_theme_stylebox_override("normal",
			panel_style(normal_bg, BTN_BORDER_HOVER, radius, 2))
	btn.add_theme_stylebox_override("hover",
			panel_style(hover_bg, Color8(184, 146, 110, 255), radius, 2))
	btn.add_theme_stylebox_override("pressed",
			panel_style(pressed_bg, BTN_BORDER, radius, 2))
	btn.add_theme_stylebox_override("disabled",
			panel_style(PANEL_BG_DARK, PANEL_BORDER_DARK, radius, 1))
	btn.add_theme_stylebox_override("focus",
			panel_style(BTN_BG_HOVER, BTN_BORDER_HOVER, radius, 2))
	btn.add_theme_color_override("font_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_pressed_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_focus_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_disabled_color", TEXT_MUTED)


func menu_separator() -> ColorRect:
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(MENU_2.r, MENU_2.g, MENU_2.b, 0.45)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep
