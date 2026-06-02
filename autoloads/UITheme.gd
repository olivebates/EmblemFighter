extends Node

# --- Panel chrome ---
const PANEL_BG := Color(0.039, 0.039, 0.055, 0.92)
const PANEL_BG_DARK := Color(0.025, 0.025, 0.045, 0.95)
const PANEL_BORDER := Color(0.35, 0.38, 0.48, 0.55)
const PANEL_RADIUS := 6
const PANEL_RADIUS_SM := 4

# --- Typography ---
const FONT_XS := 8
const FONT_SM := 10
const FONT_MD := 12
const FONT_LG := 16
const FONT_XL := 20
const FONT_DAMAGE := 22

const TEXT_PRIMARY := Color(0.92, 0.94, 0.98)
const TEXT_MUTED := Color(0.58, 0.62, 0.72)
const TEXT_SUBTLE := Color(0.72, 0.74, 0.82)

# --- Faction tints ---
const HERO_ACCENT := Color(0.35, 0.92, 0.52)
const ENEMY_ACCENT := Color(1.0, 0.42, 0.38)
const MILESTONE := Color(1.0, 0.75, 0.3)

# --- Tile highlights (lower alpha) ---
const COLOR_MOVE := Color(0.2, 0.78, 0.28, 0.22)
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
