class_name BattleHUD
extends CanvasLayer

signal radial_skill_selected(index: int)
signal radial_end_pressed
signal radial_skill_hovered(index: int)
signal skill_bar_selected(index: int)
signal skill_bar_end_pressed
signal placement_start_pressed

@onready var skill_bar: HBoxContainer = $SkillBar
var highlight_layer: Node2D = null
@onready var turn_order_bar: HBoxContainer = $TopChrome/TimelineRoot/TurnOrderBar
@onready var _top_chrome: Control = $TopChrome
@onready var _timeline_root: Control = $TopChrome/TimelineRoot
@onready var _timeline_line: Line2D = $TopChrome/TimelineRoot/TimelineLine

var _skill_buttons: Array[Control] = []
var _skill_slot_tweens: Array[Tween] = []
var _skill_bar_hero: HeroUnit = null
var _skill_bar_bg: Control = null
var _placement_start_btn: Button = null
var _placement_bar: CenterContainer = null
const BADGE_TARGET_GAP_PX := 28.0
const BADGE_TARGET_Y_OFFSET_PX := -44.0
var _mana_bar: Control = null
var _mana_bar_fill: ColorRect = null
var _mana_bar_label: Label = null
var _radial_nodes: Array[Node] = []
var _preview_label: Label = null

var _move_highlights: Array[Node] = []
var _skill_range_highlights: Array[Node] = []
var _valid_target_highlights: Array[Node] = []
var _cursor_aoe_highlights: Array[Node] = []
var _move_skill_preview_highlights: Array[Node] = []
var _cover_highlights: Array[Node] = []
var _kill_highlights: Array[Node] = []
var _telegraph_highlights: Array[Node] = []
var _status_icons: Array[Node] = []
var _turn_order_nodes: Array[Control] = []
var _unit_glow_highlights: Array[Node] = []
var _active_skill: SkillData = null
var _active_skill_index: int = -1
var _default_skill_icon := preload("res://Sprite/Placeholder.png")
var _active_actor_ring: Node2D = null
var _active_actor_tween: Tween = null
var _tracked_active_unit: Unit = null
var _move_ghosts: Array[Node] = []
var _counter_highlights: Array[Node] = []
var _smart_preview_nodes: Array[Node] = []
var _move_outline: Array[Node] = []
var _skill_outline: Array[Node] = []
var _spawn_zone_outline: Array[Node] = []
var _walk_to_shoot_highlights: Array[Node] = []
var _extended_reach_highlights: Array[Node] = []

var _hover_panel: Panel = null
var _effects_desc_panel: Control = null
var _weakness_panel: Control = null

var _move_positions: Array[Vector2i] = []
var _skill_range_positions: Array[Vector2i] = []
var _valid_target_positions: Array[Vector2i] = []
var _kill_positions: Array[Vector2i] = []

const TILE_SIZE := Grid.TILE_SIZE

enum HighlightStyle { FILL, OUTLINE }

enum HighlightMode { NONE, MOVE, SKILL, ENEMY }

const RADIAL_RADIUS := 58.0
const SCREEN_MARGIN := 10.0
const POPUP_PAD := 8.0
const BADGE_PLACE_STEP := 16
const LINE_BLOCKER_PAD := 12.0
const BADGE_WIDTH := 152.0
const BADGE_SKILL_NAME_COLOR := Color(0.96, 0.92, 0.78)

var _highlight_mode: HighlightMode = HighlightMode.NONE
var _detail_chips_visible: bool = false

var _battle: Node2D = null
var _layout_grid: Grid = null
var _smart_preview_tiles: Array[Vector2i] = []
var _screen_popup_layer: Control = null
var _hero_skill_screen_popup: Control = null
var _popup_anchor_unit: Unit = null
var _smart_preview_badge: Control = null
var _smart_cast_key: String = ""
var _badge_hover_grid: Vector2i = Vector2i(-9999, -9999)

const BADGE_SEARCH_RINGS := 64
const BADGE_HOVER_UNSET := Vector2i(-9999, -9999)

func _ready() -> void:
	add_to_group("battle_hud")

	_preview_label = Label.new()
	UITheme.apply_font(_preview_label, UITheme.FONT_SM)
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.custom_minimum_size = Vector2(220, 32)
	_preview_label.size = Vector2(220, 80)
	add_child(_preview_label)

	_screen_popup_layer = Control.new()
	_screen_popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_popup_layer.z_index = 150
	add_child(_screen_popup_layer)

	_weakness_panel = _create_weakness_panel()
	_weakness_panel.visible = false
	_screen_popup_layer.add_child(_weakness_panel)
	_weakness_panel.position = Vector2(8.0, 44.0)

	_skill_bar_bg = _create_skill_bar_bg()
	_skill_bar_bg.visible = false
	add_child(_skill_bar_bg)
	move_child(_skill_bar_bg, skill_bar.get_index())

	_mana_bar = _create_mana_bar_widget()
	_mana_bar.visible = false
	add_child(_mana_bar)
	_build_placement_bar()

func set_highlight_mode(mode: HighlightMode) -> void:
	if _highlight_mode == mode:
		return
	_highlight_mode = mode
	if mode != HighlightMode.MOVE and mode != HighlightMode.SKILL:
		_free_list(_move_highlights)
		_free_list(_cover_highlights)
		_free_list(_move_outline)
		_move_positions.clear()
	if mode != HighlightMode.SKILL:
		_free_list(_skill_outline)
		_free_list(_skill_range_highlights)
		_free_list(_valid_target_highlights)
		_free_list(_cursor_aoe_highlights)
		_free_list(_move_skill_preview_highlights)
		_free_list(_walk_to_shoot_highlights)
		_free_list(_extended_reach_highlights)
		_free_list(_kill_highlights)
		_skill_range_positions.clear()
		_valid_target_positions.clear()
		_kill_positions.clear()
	if mode != HighlightMode.ENEMY:
		clear_enemy_telegraph()
		clear_counter_highlights()

func set_layout_context(battle: Node2D, grid: Grid) -> void:
	_battle = battle
	_layout_grid = grid
	highlight_layer = battle.get_node("HighlightLayer")

func _process(_delta: float) -> void:
	var want_detail := Input.is_key_pressed(KEY_ALT)
	if want_detail != _detail_chips_visible:
		_detail_chips_visible = want_detail
		_refresh_badge_chip_visibility()
	if (_tracked_active_unit and is_instance_valid(_tracked_active_unit)
			and _active_actor_ring and is_instance_valid(_active_actor_ring)
			and _layout_grid):
		_active_actor_ring.position = _layout_grid.grid_to_world(_tracked_active_unit.grid_pos)
	_layout_hero_skill_popup()
	_layout_damage_preview()
	if _skill_bar_hero and is_instance_valid(_skill_bar_hero):
		_update_mana_bar(_skill_bar_hero)
	if _placement_start_btn and is_instance_valid(_placement_start_btn) and _skill_bar_bg.visible:
		_reposition_placement_bar()

func _viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size

func _grid_to_screen(grid_pos: Vector2i) -> Vector2:
	if _layout_grid == null or _battle == null:
		return Vector2.ZERO
	return _battle.get_canvas_transform() * _layout_grid.grid_to_world(grid_pos)

func _tile_screen_rect(grid_pos: Vector2i, expand: float = 3.0) -> Rect2:
	var center := _grid_to_screen(grid_pos)
	var half := TILE_SIZE * 0.5 + expand
	return Rect2(center.x - half, center.y - half, half * 2.0, half * 2.0)

func _collect_unit_screen_rects() -> Array[Rect2]:
	var blocked: Array[Rect2] = []
	if _battle == null:
		return blocked
	var units_layer := _battle.get_node_or_null("UnitsLayer")
	if units_layer == null:
		return blocked
	for child in units_layer.get_children():
		if child is Unit:
			blocked.append(_tile_screen_rect(child.grid_pos, 6.0))
	return blocked

func _segment_screen_rect(a: Vector2, b: Vector2, padding: float) -> Rect2:
	var min_x := minf(a.x, b.x) - padding
	var min_y := minf(a.y, b.y) - padding
	var max_x := maxf(a.x, b.x) + padding
	var max_y := maxf(a.y, b.y) + padding
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

func _collect_preview_line_blockers() -> Array[Rect2]:
	var blockers: Array[Rect2] = []
	for n in _smart_preview_nodes:
		if not n is Line2D:
			continue
		var line := n as Line2D
		if line.has_meta("grid_path"):
			var path: Array = line.get_meta("grid_path")
			for i in range(path.size() - 1):
				var a := _grid_to_screen(path[i] as Vector2i)
				var b := _grid_to_screen(path[i + 1] as Vector2i)
				blockers.append(_segment_screen_rect(a, b, LINE_BLOCKER_PAD))
			continue
		for i in range(line.points.size() - 1):
			var a := _battle.get_canvas_transform() * line.points[i] if _battle else line.points[i]
			var b := _battle.get_canvas_transform() * line.points[i + 1] if _battle else line.points[i + 1]
			blockers.append(_segment_screen_rect(a, b, LINE_BLOCKER_PAD))
	return blockers

func _collect_badge_blockers() -> Array[Rect2]:
	var blocked := _collect_unit_screen_rects()
	for line_rect in _collect_preview_line_blockers():
		blocked.append(line_rect)
	return blocked

func set_badge_hover_grid(grid_pos: Vector2i) -> void:
	_badge_hover_grid = grid_pos

func _resolve_badge_anchor_grid(fallback_grid: Vector2i) -> Vector2i:
	if _badge_hover_grid != BADGE_HOVER_UNSET:
		return _badge_hover_grid
	return fallback_grid

func _collect_blocked_screen_rects() -> Array[Rect2]:
	var blocked := _collect_badge_blockers()
	var seen: Dictionary = {}
	for pos in _move_positions:
		if seen.has(pos):
			continue
		seen[pos] = true
		blocked.append(_tile_screen_rect(pos))
	for pos in _skill_range_positions:
		if seen.has(pos):
			continue
		seen[pos] = true
		blocked.append(_tile_screen_rect(pos))
	for pos in _valid_target_positions:
		if seen.has(pos):
			continue
		seen[pos] = true
		blocked.append(_tile_screen_rect(pos))
	for pos in _smart_preview_tiles:
		if seen.has(pos):
			continue
		seen[pos] = true
		blocked.append(_tile_screen_rect(pos))
	return blocked

func _collect_ui_chrome_rects() -> Array[Rect2]:
	var chrome: Array[Rect2] = []
	if _top_chrome and _top_chrome.visible:
		chrome.append(Rect2(_top_chrome.global_position, _top_chrome.size))
	if skill_bar and skill_bar.visible:
		chrome.append(Rect2(skill_bar.global_position, skill_bar.size))
	if _mana_bar and _mana_bar.visible:
		chrome.append(Rect2(_mana_bar.global_position, _mana_bar.size))
	if _placement_bar and _placement_bar.visible:
		chrome.append(Rect2(_placement_bar.global_position, _placement_bar.size))
	if _skill_bar_bg and _skill_bar_bg.visible:
		chrome.append(Rect2(_skill_bar_bg.global_position, _skill_bar_bg.size))
	if _preview_label and _preview_label.text != "":
		chrome.append(Rect2(_preview_label.global_position, _preview_label.size))
	return chrome

func _clamp_popup_pos(pos: Vector2, popup_size: Vector2) -> Vector2:
	return Utils.clamp_popup_pos(pos, popup_size, _viewport_size(), SCREEN_MARGIN)

func _popup_fits(pos: Vector2, popup_size: Vector2, blocked: Array[Rect2]) -> bool:
	return Utils.popup_fits(pos, popup_size, blocked, _viewport_size(), SCREEN_MARGIN)

func _place_popup_rect(popup_size: Vector2, anchor: Vector2, blocked: Array[Rect2]) -> Vector2:
	return Utils.place_popup_rect(popup_size, anchor, blocked, _viewport_size(), SCREEN_MARGIN, POPUP_PAD)

func _snap_screen_to_step(v: float) -> float:
	return snapped(v, BADGE_PLACE_STEP)

func _snap_screen_pos_to_step(pos: Vector2) -> Vector2:
	return Vector2(_snap_screen_to_step(pos.x), _snap_screen_to_step(pos.y))

func _badge_popup_rect(pos: Vector2, popup_size: Vector2) -> Rect2:
	return Rect2(pos, popup_size)

func _badge_overlaps_blockers(pos: Vector2, popup_size: Vector2, blocked: Array[Rect2]) -> bool:
	var r := _badge_popup_rect(pos, popup_size)
	for b in blocked:
		if r.intersects(b):
			return true
	return false

func _badge_fully_onscreen(pos: Vector2, popup_size: Vector2) -> bool:
	return Utils.rect_fully_onscreen(pos, popup_size, _viewport_size(), SCREEN_MARGIN)

func _badge_rect_fits(pos: Vector2, popup_size: Vector2, blocked: Array[Rect2]) -> bool:
	return (_badge_fully_onscreen(pos, popup_size)
			and not _badge_overlaps_blockers(pos, popup_size, blocked))

func _place_skill_badge(anchor_grid: Vector2i, popup_size: Vector2) -> Vector2:
	var blocked := _collect_badge_blockers()
	blocked.append(_tile_screen_rect(anchor_grid, 6.0))
	var tile_center := _grid_to_screen(anchor_grid)
	var origin_y := _snap_screen_to_step(tile_center.y - popup_size.y * 0.5)
	var origin_x := _snap_screen_to_step(tile_center.x - popup_size.x * 0.5)
	var origin := Vector2(origin_x, origin_y)

	var placed := _slide_badge_horizontal(origin, popup_size, blocked, 1)
	if placed.x >= 0.0:
		return placed
	placed = _slide_badge_horizontal(origin, popup_size, blocked, -1)
	if placed.x >= 0.0:
		return placed
	return _clamp_popup_pos(origin, popup_size)

func _slide_badge_horizontal(origin: Vector2, popup_size: Vector2, blocked: Array[Rect2],
		direction: int) -> Vector2:
	var start_step := 0 if direction > 0 else 1
	for step in range(start_step, BADGE_SEARCH_RINGS):
		var candidate := Vector2(
			_snap_screen_to_step(origin.x + float(step * direction * BADGE_PLACE_STEP)),
			origin.y)
		if not _badge_fully_onscreen(candidate, popup_size):
			return Vector2(-1.0, 0.0)
		if not _badge_overlaps_blockers(candidate, popup_size, blocked):
			return candidate
	return Vector2(-1.0, 0.0)

func _position_skill_badge(panel: Control, fallback_grid: Vector2i) -> void:
	if panel == null:
		return
	var anchor := _resolve_badge_anchor_grid(fallback_grid)
	panel.set_meta("badge_anchor_grid", anchor)
	panel.set_meta("badge_fallback_grid", fallback_grid)
	var sz := _measure_control(panel)
	panel.position = _place_skill_badge(anchor, sz)

func _position_badge_for_targets(badge: Control, fallback_grid: Vector2i) -> void:
	if badge == null:
		return
	badge.set_meta("badge_fallback_grid", fallback_grid)
	var sz = _badge_stack_size(badge)
	var target_positions = badge.get_meta("target_positions", []) as Array
	var vp = _viewport_size()
	var half_tile = TILE_SIZE * 0.5
	var gap = BADGE_TARGET_GAP_PX
	if not target_positions.is_empty():
		var hero_grid_pos = badge.get_meta("hero_grid", fallback_grid) as Vector2i
		var primary_target = target_positions[0] as Vector2i
		var place_left = primary_target.x < hero_grid_pos.x
		badge.set_meta("badge_place_left", place_left)
		var target_sp = _grid_to_screen(primary_target)
		if target_positions.size() > 1:
			var sum_x = 0.0
			var sum_y = 0.0
			for pos in target_positions:
				var sp = _grid_to_screen(pos as Vector2i)
				sum_x += sp.x
				sum_y += sp.y
			target_sp = Vector2(sum_x / float(target_positions.size()),
				sum_y / float(target_positions.size()))
		badge.set_meta("badge_target_screen_y", target_sp.y)
		var target_left = target_sp.x - half_tile
		var target_right = target_sp.x + half_tile
		var badge_x: float
		if place_left:
			badge_x = target_left - gap - sz.x
		else:
			badge_x = target_right + gap
		badge_x = clampf(badge_x, SCREEN_MARGIN, vp.x - sz.x - SCREEN_MARGIN)
		badge.position = Vector2(badge_x, badge.position.y)
		_layout_attack_popups(badge)
		return
	var anchor = _resolve_badge_anchor_grid(fallback_grid)
	badge.set_meta("badge_anchor_grid", anchor)
	badge.position = _place_skill_badge(anchor, sz)

func _relayout_skill_badges() -> void:
	if (_hero_skill_screen_popup and is_instance_valid(_hero_skill_screen_popup)
			and _popup_anchor_unit and is_instance_valid(_popup_anchor_unit)):
		var fallback: Vector2i = _hero_skill_screen_popup.get_meta(
			"badge_fallback_grid", _popup_anchor_unit.grid_pos)
		_position_badge_for_targets(_hero_skill_screen_popup, fallback)
	if _smart_preview_badge and is_instance_valid(_smart_preview_badge):
		var fallback: Vector2i = _smart_preview_badge.get_meta(
			"badge_fallback_grid", Vector2i(-999, -999))
		if fallback != Vector2i(-999, -999):
			_position_badge_for_targets(_smart_preview_badge, fallback)

func _place_popup_near_tile(grid_pos: Vector2i, popup_size: Vector2) -> Vector2:
	return _place_skill_badge(grid_pos, popup_size)

func _measure_control(ctrl: Control) -> Vector2:
	if ctrl == null:
		return Vector2.ZERO
	return ctrl.get_combined_minimum_size()

func _badge_stack_size(badge: Control) -> Vector2:
	if badge == null:
		return Vector2.ZERO
	var stack = badge.get_child(0) as Control
	if stack == null:
		return _measure_control(badge)
	stack.queue_sort()
	var sz = stack.get_combined_minimum_size()
	sz.x = maxf(sz.x, BADGE_WIDTH)
	return sz

func _panel_layout_size(panel: PanelContainer) -> Vector2:
	if panel == null:
		return Vector2.ZERO
	panel.queue_sort()
	panel.reset_size()
	return panel.get_combined_minimum_size()

func _weapon_mult_damage_color(weapon_mult: float) -> Color:
	if weapon_mult > 1.0:
		return Color(0.38, 0.95, 0.48)
	if weapon_mult < 1.0:
		return Color(0.95, 0.38, 0.38)
	return Color(0.95, 0.88, 0.35)

func _preview_panel_tint(previews: Array) -> Color:
	if previews.is_empty():
		return _weapon_mult_damage_color(1.0)
	if previews[0].get("is_heal", false):
		return UITheme.COLOR_HEAL
	return _weapon_mult_damage_color(previews[0].weapon_mult)

func _sync_effects_panel_tint(tint: Color) -> void:
	if _effects_desc_panel == null or not is_instance_valid(_effects_desc_panel):
		return
	_effects_desc_panel.add_theme_stylebox_override("panel", UITheme.badge_panel_style(tint))

func _apply_badge_panel_styles(badge: Control, tint: Color) -> void:
	badge.set_meta("badge_panel_tint", tint)
	badge.set_meta("badge_tint", tint)
	var panel = badge.find_child("BadgePanel", true, false) as PanelContainer
	if panel:
		panel.add_theme_stylebox_override("panel", UITheme.badge_panel_style(tint))
	var hdr = badge.find_child("HeaderLabel", true, false) as Label
	if hdr:
		var header_strip = hdr.get_parent() as PanelContainer
		if header_strip:
			header_strip.add_theme_stylebox_override(
				"panel", UITheme.badge_header_style(tint, hdr.text))
	var caret = badge.find_child("BadgeCaret", true, false) as Label
	if caret:
		caret.modulate = Color(tint.r, tint.g, tint.b, 0.8)
	var atk_type_lbl = badge.find_child("AttackTypeLabel", true, false) as Label
	if atk_type_lbl:
		atk_type_lbl.modulate = tint.lightened(0.12)
	_sync_effects_panel_tint(tint)

func _layout_attack_popups(badge: Control) -> void:
	if badge == null:
		return
	var target_y = float(badge.get_meta("badge_target_screen_y", -1.0))
	if target_y < 0.0:
		return
	var badge_sz = _badge_stack_size(badge)
	badge.size = badge_sz
	var desc_sz = Vector2.ZERO
	var desc_panel: PanelContainer = null
	if _effects_desc_panel and is_instance_valid(_effects_desc_panel):
		desc_panel = _effects_desc_panel as PanelContainer
		desc_sz = _panel_layout_size(desc_panel)
		_effects_desc_panel.size = desc_sz
	var shared_h = maxf(badge_sz.y, desc_sz.y)
	var vp = _viewport_size()
	var pair_top = clampf(
			target_y - shared_h * 0.5 + BADGE_TARGET_Y_OFFSET_PX,
			SCREEN_MARGIN, vp.y - shared_h - SCREEN_MARGIN)
	badge.position.y = pair_top + (shared_h - badge_sz.y) * 0.5
	if desc_panel == null:
		return
	var gap = 6.0
	var place_left = bool(badge.get_meta("badge_place_left", false))
	var desc_x: float
	if place_left:
		desc_x = badge.position.x - desc_sz.x - gap
	else:
		desc_x = badge.position.x + badge_sz.x + gap
	desc_x = clampf(desc_x, SCREEN_MARGIN, vp.x - desc_sz.x - SCREEN_MARGIN)
	desc_panel.position = Vector2(desc_x, pair_top + (shared_h - desc_sz.y) * 0.5)

func _layout_damage_preview() -> void:
	if _preview_label == null or _preview_label.text == "":
		return
	_preview_label.reset_size()
	var sz := _preview_label.get_minimum_size()
	if sz.y < 8.0:
		sz = _preview_label.size
	var blocked := _collect_blocked_screen_rects()
	var vp := _viewport_size()
	var anchor := Vector2(SCREEN_MARGIN, vp.y - sz.y - SCREEN_MARGIN - 56.0)
	_preview_label.position = _place_popup_rect(sz, anchor, blocked)

func _layout_hero_skill_popup() -> void:
	_relayout_skill_badges()
	_relayout_effects_panel()

# --- Skill bar ---

func _skill_icon_texture(hero: HeroUnit, skill_index: int, skill: SkillData) -> Texture2D:
	if hero != null:
		var icon := hero.get_skill_icon(skill_index)
		if icon:
			return icon
	if skill and skill.icon:
		return Utils.sprite_frame(skill.icon)
	return Utils.sprite_frame(_default_skill_icon)

func _skills_remaining(hero: HeroUnit) -> int:
	var n := 0
	for i in hero.skills.size():
		if not hero.skill_used(i):
			n += 1
	return n

func show_skill_bar(hero: HeroUnit, states: Array, highlight_index: int) -> void:
	for tw in _skill_slot_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_skill_slot_tweens.clear()
	for btn in _skill_buttons:
		btn.queue_free()
	_skill_buttons.clear()
	if hero == null:
		_skill_bar_hero = null
		if _mana_bar:
			_mana_bar.visible = false
		if _skill_bar_bg:
			_skill_bar_bg.visible = false
		return

	_skill_bar_hero = hero

	var end_btn := Button.new()
	end_btn.text = "End\n(Space)"
	end_btn.custom_minimum_size = Vector2(40, 32)
	end_btn.add_theme_font_size_override("font_size", UITheme.FONT_SM)
	end_btn.add_theme_stylebox_override("normal", UITheme.panel_style())
	end_btn.add_theme_stylebox_override("hover", UITheme.panel_style(
		Color(0.06, 0.06, 0.1, 0.95), UITheme.TEXT_SUBTLE))
	end_btn.pressed.connect(func(): skill_bar_end_pressed.emit())
	skill_bar.add_child(end_btn)
	_skill_buttons.append(end_btn)

	for i in hero.skills.size():
		var skill: SkillData = hero.skills[i]
		var slot := _make_skill_icon_slot(hero, i, skill,
				states[i] if i < states.size() else BattleManager.SkillState.USED,
				i == highlight_index)
		skill_bar.add_child(slot)
		_skill_buttons.append(slot)

	if _skill_bar_bg:
		_skill_bar_bg.visible = true
	if _placement_bar:
		_placement_bar.visible = false
	skill_bar.visible = true
	_update_mana_bar(hero)
	call_deferred("_reposition_skill_bar")

const _SKILL_HOTKEYS = ["Q", "W", "E", "R"]

func _make_skill_icon_slot(hero: HeroUnit, skill_index: int, skill: SkillData,
		state_val: int, is_active: bool) -> Control:
	var tint := skill.get_display_tint(skill_index)
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(32, 32)
	wrapper.mouse_filter = Control.MOUSE_FILTER_STOP
	wrapper.tooltip_text = skill.display_name
	var _captured_index = skill_index
	wrapper.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			skill_bar_selected.emit(_captured_index))

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UITheme.tinted_panel_style(tint, is_active))
	wrapper.add_child(panel)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)

	var tex := TextureRect.new()
	tex.custom_minimum_size = Vector2(24, 24)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture = _skill_icon_texture(hero, skill_index, skill)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match state_val:
		BattleManager.SkillState.USED:
			tex.modulate = Color(0.35, 0.35, 0.35, 0.45)
		_:
			tex.modulate = Color.WHITE
	center.add_child(tex)

	if state_val == BattleManager.SkillState.USED:
		var check := Label.new()
		check.text = "✓"
		check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		check.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		UITheme.apply_font(check, UITheme.FONT_LG, UITheme.HERO_ACCENT)
		check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(check)
	elif state_val == BattleManager.SkillState.NO_MANA:
		var dark = ColorRect.new()
		dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dark.color = Color(0.0, 0.0, 0.0, 0.9)
		dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(dark)

	if is_active:
		wrapper.scale = Vector2(1.1, 1.1)
		var ring := ColorRect.new()
		ring.name = "ActiveRing"
		ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ring.offset_left = -3
		ring.offset_top = -3
		ring.offset_right = 3
		ring.offset_bottom = 3
		ring.color = Color(tint.r, tint.g, tint.b, 0.55)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.z_index = -1
		wrapper.add_child(ring)
		ring.show_behind_parent = true
		var glow := panel.create_tween().set_loops()
		glow.tween_property(panel, "modulate", Color(1.18, 1.14, 1.05, 1.0), 0.38)
		glow.tween_property(panel, "modulate", Color.WHITE, 0.38)
		_skill_slot_tweens.append(glow)

	# Hotkey label: top-left corner (Q/W/E/R)
	if skill_index < _SKILL_HOTKEYS.size():
		var hotkey_lbl := Label.new()
		hotkey_lbl.text = _SKILL_HOTKEYS[skill_index]
		hotkey_lbl.position = Vector2(2, 1)
		hotkey_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hotkey_lbl.z_index = 2
		UITheme.apply_font(hotkey_lbl, UITheme.FONT_SM, Color(1.0, 1.0, 1.0, 0.85))
		wrapper.add_child(hotkey_lbl)

	# Mana cost label: bottom-left corner
	var mana_lbl := Label.new()
	mana_lbl.text = str(skill.mana_cost)
	mana_lbl.position = Vector2(2, 20)
	mana_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mana_lbl.z_index = 2
	UITheme.apply_font(mana_lbl, UITheme.FONT_SM, Color(0.45, 0.65, 1.0, 1.0))
	wrapper.add_child(mana_lbl)

	return wrapper

func _reposition_skill_bar() -> void:
	if skill_bar == null:
		return
	skill_bar.reset_size()
	var vp = _viewport_size()
	var bar_size = skill_bar.get_combined_minimum_size()
	var pad_h = 8.0
	var pad_v = 6.0
	var mana_h = 12.0
	var mana_gap = 4.0
	var total_h = bar_size.y + mana_gap + mana_h + pad_v * 2.0
	var bg_y = vp.y - total_h
	skill_bar.position = Vector2(
		(vp.x - bar_size.x) * 0.5,
		bg_y + pad_v)
	if _mana_bar:
		var mana_w = bar_size.x
		_mana_bar.size = Vector2(mana_w, mana_h)
		_mana_bar.position = Vector2(skill_bar.position.x, skill_bar.position.y + bar_size.y + mana_gap)
	if _skill_bar_bg and _skill_bar_bg.visible:
		_skill_bar_bg.size = Vector2(vp.x + 2.0, vp.y - bg_y + 1.0)
		_skill_bar_bg.position = Vector2(-1.0, bg_y)

func _build_placement_bar() -> void:
	_placement_bar = CenterContainer.new()
	_placement_bar.name = "PlacementBar"
	_placement_bar.visible = false
	_placement_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_placement_bar)
	var btn := _ensure_placement_start_button()
	if btn.get_parent() != _placement_bar:
		if btn.get_parent():
			btn.get_parent().remove_child(btn)
		_placement_bar.add_child(btn)

func _ensure_placement_start_button() -> Button:
	if _placement_start_btn != null and is_instance_valid(_placement_start_btn):
		return _placement_start_btn
	var btn := Button.new()
	btn.text = "Start Combat"
	btn.custom_minimum_size = Vector2(220, 56)
	UITheme.apply_prominent_button_theme(btn, 6)
	btn.pressed.connect(func(): placement_start_pressed.emit())
	_placement_start_btn = btn
	return btn

func _clear_skill_slots() -> void:
	for tw in _skill_slot_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_skill_slot_tweens.clear()
	for btn in _skill_buttons:
		btn.queue_free()
	_skill_buttons.clear()
	_skill_bar_hero = null
	if _mana_bar:
		_mana_bar.visible = false

func enter_placement_phase() -> void:
	_clear_skill_slots()
	skill_bar.visible = false
	if _mana_bar:
		_mana_bar.visible = false
	var btn := _ensure_placement_start_button()
	if _placement_bar == null:
		_build_placement_bar()
	elif btn.get_parent() != _placement_bar:
		if btn.get_parent():
			btn.get_parent().remove_child(btn)
		_placement_bar.add_child(btn)
	btn.visible = true
	btn.disabled = false
	if _placement_bar:
		_placement_bar.visible = true
	if _skill_bar_bg:
		_skill_bar_bg.visible = true
		_skill_bar_bg.modulate = Color.WHITE
	layer = 11
	_reposition_placement_bar()
	call_deferred("_reposition_placement_bar")

func show_placement_bar(start_btn: Button = null) -> void:
	if start_btn != null and start_btn != _placement_start_btn:
		if _placement_start_btn and is_instance_valid(_placement_start_btn):
			_placement_start_btn.queue_free()
		_placement_start_btn = start_btn
	enter_placement_phase()

func hide_placement_bar() -> void:
	if _placement_bar:
		_placement_bar.visible = false
	if _placement_start_btn and is_instance_valid(_placement_start_btn):
		_placement_start_btn.visible = false
	if layer > 0:
		layer = 0

func get_bottom_chrome_height() -> float:
	if _skill_bar_bg and _skill_bar_bg.visible:
		return _skill_bar_bg.size.y
	return 88.0

func _reposition_placement_bar() -> void:
	if _placement_start_btn == null or not is_instance_valid(_placement_start_btn):
		return
	_placement_start_btn.reset_size()
	var vp := _viewport_size()
	var btn_size := _placement_start_btn.get_combined_minimum_size()
	var pad_v := 14.0
	var total_h := btn_size.y + pad_v * 2.0
	var bg_y := vp.y - total_h
	if _placement_bar:
		_placement_bar.position = Vector2(0.0, bg_y)
		_placement_bar.size = Vector2(vp.x, total_h)
	if _skill_bar_bg and _skill_bar_bg.visible:
		_skill_bar_bg.size = Vector2(vp.x + 2.0, vp.y - bg_y + 1.0)
		_skill_bar_bg.position = Vector2(-1.0, bg_y)

func is_mouse_over_skill_panel() -> bool:
	var mouse = get_viewport().get_mouse_position()
	if _placement_bar and _placement_bar.visible:
		if Rect2(_placement_bar.global_position, _placement_bar.size).has_point(mouse):
			return true
	if _skill_bar_bg == null or not _skill_bar_bg.visible:
		return false
	return Rect2(_skill_bar_bg.global_position, _skill_bar_bg.size).has_point(mouse)

func _create_skill_bar_bg() -> Control:
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.08, 0.88)
	style.border_color = Color(0.2, 0.22, 0.3, 0.7)
	style.set_border_width_all(1)
	style.border_blend = false
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _create_mana_bar_widget() -> Control:
	var container = Control.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.size = Vector2(300, 12)

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.08, 0.16, 0.9)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bg)

	var fill = ColorRect.new()
	fill.color = Color(0.25, 0.45, 1.0, 0.9)
	fill.position = Vector2(1, 1)
	fill.size = Vector2(298, 10)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(fill)
	_mana_bar_fill = fill

	var lbl = Label.new()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_font(lbl, UITheme.FONT_SM, Color(0.85, 0.9, 1.0, 1.0))
	container.add_child(lbl)
	_mana_bar_label = lbl

	return container

func _update_mana_bar(hero: HeroUnit) -> void:
	if _mana_bar == null or _mana_bar_fill == null or _mana_bar_label == null:
		return
	if not is_instance_valid(hero):
		return
	_mana_bar.visible = true
	var ratio = float(hero.mana) / float(maxi(hero.max_mana, 1))
	var bar_w = maxi(int(_mana_bar.size.x) - 2, 1)
	_mana_bar_fill.size = Vector2(int(bar_w * ratio), 10)
	_mana_bar_label.text = "%d / %d" % [hero.mana, hero.max_mana]

# --- In-world active skill indicator ---

func show_active_skill_on_hero(hero: HeroUnit, skill: SkillData, skill_index: int, _grid: Node,
		previews: Array = []) -> void:
	if hero == null or skill == null:
		clear_active_skill_on_hero()
		return
	if skill_index < 0:
		skill_index = hero.skills.find(skill)
	var tint := _weapon_mult_damage_color(1.0)
	if (_hero_skill_screen_popup and is_instance_valid(_hero_skill_screen_popup)
			and _popup_anchor_unit == hero):
		_active_skill = skill
		_active_skill_index = skill_index
		_update_badge_identity(_hero_skill_screen_popup, hero, skill, skill_index, tint, "ACTIVE")
		_hero_skill_screen_popup.set_meta("hero_grid", hero.grid_pos)
		_update_badge_previews(_hero_skill_screen_popup, previews)
		_position_badge_for_targets(_hero_skill_screen_popup, hero.grid_pos)
		return
	clear_active_skill_on_hero()
	_active_skill = skill
	_active_skill_index = skill_index
	_popup_anchor_unit = hero
	_hero_skill_screen_popup = _create_skill_badge(
		hero, skill, skill_index, tint, "ACTIVE", previews)
	_hero_skill_screen_popup.set_meta("hero_grid", hero.grid_pos)
	if _screen_popup_layer:
		_screen_popup_layer.add_child(_hero_skill_screen_popup)
		_position_badge_for_targets(_hero_skill_screen_popup, hero.grid_pos)
		_play_badge_spawn(_hero_skill_screen_popup)

func update_active_skill_badge_damage(previews: Array) -> void:
	if _hero_skill_screen_popup == null or not is_instance_valid(_hero_skill_screen_popup):
		return
	_update_badge_previews(_hero_skill_screen_popup, previews)
	_position_badge_for_targets(_hero_skill_screen_popup, _popup_anchor_unit.grid_pos)

func clear_active_skill_on_hero() -> void:
	if _hero_skill_screen_popup and is_instance_valid(_hero_skill_screen_popup):
		_hero_skill_screen_popup.queue_free()
	_hero_skill_screen_popup = null
	_popup_anchor_unit = null
	_active_skill = null
	_active_skill_index = -1
	_free_effects_desc_panel()

func _clear_smart_preview_badge() -> void:
	if _smart_preview_badge and is_instance_valid(_smart_preview_badge):
		_smart_preview_badge.queue_free()
	_smart_preview_badge = null
	_smart_cast_key = ""
	_free_effects_desc_panel()

func _smart_cast_key_for(hero: HeroUnit, cast_pos: Vector2i) -> String:
	return "%d_%s" % [hero.get_instance_id(), cast_pos]

func _create_skill_badge(hero: HeroUnit, skill: SkillData, skill_index: int, tint: Color,
		header: String, previews: Array = []) -> Control:
	var wrapper := Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.custom_minimum_size = Vector2(BADGE_WIDTH, 0)

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 0)
	wrapper.add_child(stack)
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.name = "BadgePanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UITheme.badge_panel_style(tint))
	stack.add_child(panel)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	if header != "WILL USE":
		var header_strip := PanelContainer.new()
		header_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header_strip.add_theme_stylebox_override("panel", UITheme.badge_header_style(tint, header))
		col.add_child(header_strip)

		var hdr := Label.new()
		hdr.name = "HeaderLabel"
		hdr.text = header
		hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hdr.add_theme_font_size_override("font_size", UITheme.FONT_XS)
		hdr.modulate = UITheme.TEXT_PRIMARY
		hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header_strip.add_child(hdr)

		col.add_child(_make_badge_separator())
	else:
		col.add_child(_make_badge_separator())

	var identity := HBoxContainer.new()
	identity.name = "IdentityRow"
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_theme_constant_override("separation", 6)
	col.add_child(identity)

	var tex := TextureRect.new()
	tex.name = "SkillIcon"
	tex.custom_minimum_size = Vector2(30, 30)
	tex.texture = _skill_icon_texture(hero, skill_index, skill)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.modulate = Color.WHITE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(tex)

	var name_col := VBoxContainer.new()
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.add_theme_constant_override("separation", 2)
	identity.add_child(name_col)

	var name_lbl := Label.new()
	name_lbl.name = "SkillName"
	name_lbl.text = skill.display_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_MD)
	name_lbl.modulate = BADGE_SKILL_NAME_COLOR
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(name_lbl)

	var atk_type_lbl := Label.new()
	atk_type_lbl.name = "AttackTypeLabel"
	atk_type_lbl.text = _attack_type_label_text(skill, 1.0)
	atk_type_lbl.add_theme_font_size_override("font_size", UITheme.FONT_XS)
	atk_type_lbl.modulate = tint.lightened(0.12)
	atk_type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(atk_type_lbl)

	var dmg_sep := _make_badge_separator()
	dmg_sep.name = "DamageSeparator"
	col.add_child(dmg_sep)

	var dmg_box := VBoxContainer.new()
	dmg_box.name = "DamageBreakdown"
	dmg_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dmg_box.add_theme_constant_override("separation", 5)
	col.add_child(dmg_box)

	var target_rows := VBoxContainer.new()
	target_rows.name = "TargetRows"
	target_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_rows.add_theme_constant_override("separation", 6)
	dmg_box.add_child(target_rows)

	var total_row := HBoxContainer.new()
	total_row.name = "TotalRow"
	total_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dmg_box.add_child(total_row)

	var total_lbl := Label.new()
	total_lbl.text = "TOTAL"
	total_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_lbl.add_theme_font_size_override("font_size", UITheme.FONT_XS)
	total_lbl.modulate = UITheme.TEXT_SUBTLE
	total_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	total_row.add_child(total_lbl)

	var total_dmg := Label.new()
	total_dmg.name = "TotalDamage"
	total_dmg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total_dmg.add_theme_font_size_override("font_size", 14)
	total_dmg.modulate = Color(0.95, 0.88, 0.55)
	total_dmg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	total_row.add_child(total_dmg)

	wrapper.set_meta("skill", skill)
	wrapper.set_meta("badge_tint", tint)
	wrapper.set_meta("target_positions", [] as Array)

	var detail_hint := Label.new()
	detail_hint.name = "DetailHint"
	detail_hint.text = "Hold Alt for breakdown"
	detail_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_hint.add_theme_font_size_override("font_size", UITheme.FONT_XS)
	detail_hint.modulate = Color(1, 1, 1, 0.32)
	detail_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(detail_hint)

	var caret := Label.new()
	caret.name = "BadgeCaret"
	caret.text = "▼"
	caret.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caret.add_theme_font_size_override("font_size", 7)
	caret.modulate = Color(tint.r, tint.g, tint.b, 0.8)
	caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(caret)

	_update_badge_previews(wrapper, previews)
	_update_badge_effects(wrapper, skill)
	return wrapper

func _make_badge_separator() -> ColorRect:
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(1, 1, 1, 0.1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep

func _make_modifier_chip(text: String, color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = "ModChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", UITheme.chip_style(color))
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", UITheme.FONT_XS)
	lbl.modulate = color.lightened(0.12)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	return chip

func _should_show_modifier_chips(is_kill: bool) -> bool:
	return is_kill or _detail_chips_visible

func _refresh_badge_chip_visibility() -> void:
	for badge in [_hero_skill_screen_popup, _smart_preview_badge]:
		if badge == null or not is_instance_valid(badge):
			continue
		var hint := badge.find_child("DetailHint", true, false) as Label
		if hint:
			hint.visible = true
		var target_rows := badge.find_child("TargetRows", true, false) as VBoxContainer
		if target_rows == null:
			continue
		for row in target_rows.get_children():
			_refresh_row_chip_visibility(row as VBoxContainer)
	if _weakness_panel and is_instance_valid(_weakness_panel):
		_weakness_panel.visible = _detail_chips_visible
	if _effects_desc_panel and is_instance_valid(_effects_desc_panel):
		var detail_labels = _effects_desc_panel.get_meta("effect_detail_labels", []) as Array
		for node in detail_labels:
			var desc_lbl = node as Label
			if desc_lbl == null:
				continue
			desc_lbl.visible = _detail_chips_visible
			if _detail_chips_visible:
				desc_lbl.reset_size()
		_effects_desc_panel.reset_size()
	_relayout_skill_badges()

func _refresh_row_chip_visibility(row: VBoxContainer) -> void:
	if row == null:
		return
	var mod_row := row.find_child("ModRow", true, false) as HBoxContainer
	if mod_row == null:
		return
	_apply_row_chip_visibility(mod_row)

func _row_has_visible_chip(mod_row: HBoxContainer) -> bool:
	for chip in mod_row.get_children():
		if chip.visible:
			return true
	return false

func _ensure_target_rows(target_rows: VBoxContainer, count: int) -> void:
	while target_rows.get_child_count() < count:
		target_rows.add_child(_make_target_row())
	for i in target_rows.get_child_count():
		var row := target_rows.get_child(i) as VBoxContainer
		row.visible = i < count

func _make_target_row() -> VBoxContainer:
	var row := VBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)

	var name_dmg_row := HBoxContainer.new()
	name_dmg_row.name = "NameDmgRow"
	name_dmg_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_dmg_row.add_theme_constant_override("separation", 4)
	row.add_child(name_dmg_row)

	var name_lbl := Label.new()
	name_lbl.name = "TargetName"
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.modulate = Color(0.88, 0.89, 0.94)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_dmg_row.add_child(name_lbl)

	var dmg_lbl := Label.new()
	dmg_lbl.name = "DamageValue"
	dmg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dmg_lbl.add_theme_font_size_override("font_size", 22)
	dmg_lbl.modulate = UITheme.COLOR_DAMAGE_NORMAL
	dmg_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dmg_lbl.set_meta("displayed_dmg", -1)
	name_dmg_row.add_child(dmg_lbl)

	var mod_row := HBoxContainer.new()
	mod_row.name = "ModRow"
	mod_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mod_row.add_theme_constant_override("separation", 4)
	row.add_child(mod_row)

	var kill_lbl = Label.new()
	kill_lbl.name = "KillLabel"
	kill_lbl.text = "☠ KILL"
	kill_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kill_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kill_lbl.add_theme_font_size_override("font_size", UITheme.FONT_XS * 2)
	kill_lbl.modulate = UITheme.COLOR_DAMAGE_KILL
	kill_lbl.visible = false
	kill_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(kill_lbl)

	return row

func _update_badge_previews(badge: Control, previews: Array) -> void:
	var dmg_box := badge.find_child("DamageBreakdown", true, false) as VBoxContainer
	var dmg_sep := badge.find_child("DamageSeparator", true, false) as CanvasItem
	if dmg_box == null:
		return
	var target_rows := dmg_box.find_child("TargetRows", true, false) as VBoxContainer
	var total_row := dmg_box.find_child("TotalRow", true, false) as CanvasItem
	var total_dmg := dmg_box.find_child("TotalDamage", true, false) as Label
	var tgt_positions: Array[Vector2i] = []
	for p in previews:
		var tgt = p.get("target", null)
		if tgt != null and "grid_pos" in tgt:
			tgt_positions.append(tgt.grid_pos as Vector2i)
	badge.set_meta("target_positions", tgt_positions)
	if previews.is_empty():
		dmg_box.visible = false
		if dmg_sep:
			dmg_sep.visible = false
		var empty_skill = badge.get_meta("skill", null) as SkillData
		_update_attack_type_label(badge, empty_skill, 1.0)
		return
	# Sort by highest damage / heal first so the primary target drives tint
	var sorted_previews = previews.duplicate()
	if sorted_previews.size() > 1 and not sorted_previews[0].get("is_heal", false):
		sorted_previews.sort_custom(func(a, b): return a.get("dmg", 0) > b.get("dmg", 0))
	dmg_box.visible = true
	if dmg_sep:
		dmg_sep.visible = true
	var show_names := sorted_previews.size() > 1
	_ensure_target_rows(target_rows, sorted_previews.size())
	var total := 0
	var total_base := 0
	var is_heal = sorted_previews[0].get("is_heal", false)
	var panel_tint = _preview_panel_tint(sorted_previews)
	_apply_badge_panel_styles(badge, panel_tint)
	var skill = badge.get_meta("skill", null) as SkillData
	var weapon_mult = 1.0
	if not is_heal and sorted_previews.size() > 0:
		weapon_mult = sorted_previews[0].weapon_mult
	badge.set_meta("last_weapon_mult", weapon_mult)
	_update_attack_type_label(badge, skill, weapon_mult)
	for i in sorted_previews.size():
		_update_target_row(target_rows.get_child(i) as VBoxContainer, sorted_previews[i], show_names)
		if is_heal:
			total += sorted_previews[i].get("actual_heal", sorted_previews[i].get("heal", 0))
		else:
			total += sorted_previews[i].dmg
			total_base += int(sorted_previews[i].get("base_power", 0))
	var active_badge = _hero_skill_screen_popup if (
		_hero_skill_screen_popup and is_instance_valid(_hero_skill_screen_popup)) else (
		_smart_preview_badge if _smart_preview_badge and is_instance_valid(_smart_preview_badge) else null)
	if active_badge and not tgt_positions.is_empty():
		_position_badge_for_targets(active_badge, active_badge.get_meta(
			"badge_fallback_grid", tgt_positions[0]))
	if sorted_previews.size() > 1:
		total_row.visible = true
		if total_dmg:
			total_dmg.text = ("+%d HEAL" % total) if is_heal else ("%d DMG" % total)
			if is_heal:
				total_dmg.modulate = UITheme.COLOR_HEAL
			elif not is_heal and sorted_previews.size() > 0:
				total_dmg.modulate = _weapon_mult_damage_color(sorted_previews[0].weapon_mult)
			else:
				total_dmg.modulate = Color(0.95, 0.88, 0.55)
	else:
		total_row.visible = false

func _update_target_row(row: VBoxContainer, preview: Dictionary, show_name: bool) -> void:
	var name_lbl := row.find_child("TargetName", true, false) as Label
	var dmg_lbl := row.find_child("DamageValue", true, false) as Label
	var mod_row := row.find_child("ModRow", true, false) as HBoxContainer
	if name_lbl == null or dmg_lbl == null or mod_row == null:
		return

	var target: Unit = preview.target
	var target_name := target.label.text if target and target.label else "?"
	name_lbl.text = target_name if show_name else ""
	name_lbl.visible = show_name
	if show_name:
		dmg_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
		dmg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dmg_lbl.add_theme_font_size_override("font_size", 11)
	else:
		dmg_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dmg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dmg_lbl.add_theme_font_size_override("font_size", 22)

	var target_id: int = target.get_instance_id() if target else 0
	var prev_target_id: int = int(dmg_lbl.get_meta("preview_target_id", -1))

	var is_heal: bool = preview.get("is_heal", false)
	if is_heal:
		var heal_amt: int = preview.get("heal", 0)
		var actual: int = preview.get("actual_heal", heal_amt)
		var new_val: int = actual
		var old_val: int = int(dmg_lbl.get_meta("displayed_dmg", -1))
		if target_id == prev_target_id and new_val == old_val and old_val >= 0:
			dmg_lbl.modulate = UITheme.COLOR_HEAL
			_apply_row_chip_visibility(mod_row)
			return
		dmg_lbl.set_meta("preview_target_id", target_id)
		dmg_lbl.modulate = UITheme.COLOR_HEAL
		dmg_lbl.set_meta("is_kill", false)
		var label := "+%d HEAL" % actual
		if old_val != new_val:
			if old_val < 0:
				dmg_lbl.text = label
				dmg_lbl.set_meta("displayed_dmg", new_val)
			else:
				_tween_heal_value(dmg_lbl, old_val, new_val)
		else:
			dmg_lbl.text = label
		for child in mod_row.get_children():
			mod_row.remove_child(child)
			child.free()
		mod_row.add_child(_make_modifier_chip("Base: %d HP" % heal_amt, UITheme.COLOR_HEAL))
		if actual < heal_amt:
			mod_row.add_child(_make_modifier_chip("capped", UITheme.COLOR_CHIP_MITIGATE))
		_apply_row_chip_visibility(mod_row)
		return

	var kill_lbl = row.find_child("KillLabel", true, false) as Label
	var is_kill: bool = preview.is_kill
	var new_dmg: int = preview.dmg
	var old_dmg: int = int(dmg_lbl.get_meta("displayed_dmg", -1))
	var dmg_color = _weapon_mult_damage_color(preview.weapon_mult)
	if target_id == prev_target_id and new_dmg == old_dmg and old_dmg >= 0:
		dmg_lbl.modulate = dmg_color
		if kill_lbl:
			kill_lbl.visible = is_kill
		_refresh_target_row_mod_chips(mod_row, preview)
		return
	if target_id == prev_target_id and _damage_label_tweening_to(dmg_lbl, new_dmg):
		dmg_lbl.modulate = dmg_color
		if kill_lbl:
			kill_lbl.visible = is_kill
		_refresh_target_row_mod_chips(mod_row, preview)
		return
	dmg_lbl.set_meta("preview_target_id", target_id)
	dmg_lbl.set_meta("is_kill", is_kill)
	if not is_kill:
		dmg_lbl.set_meta("kill_punch", false)
	dmg_lbl.modulate = dmg_color

	var dmg_fmt = ("−%d" if show_name else "%d DMG") % new_dmg
	if old_dmg != new_dmg:
		if old_dmg < 0:
			dmg_lbl.text = dmg_fmt
			dmg_lbl.set_meta("displayed_dmg", new_dmg)
			_play_value_punch(dmg_lbl)
		else:
			_tween_damage_value_fmt(dmg_lbl, old_dmg, new_dmg, show_name)
	else:
		dmg_lbl.text = dmg_fmt

	if kill_lbl:
		kill_lbl.visible = is_kill
	_refresh_target_row_mod_chips(mod_row, preview)

func _refresh_target_row_mod_chips(mod_row: HBoxContainer, preview: Dictionary) -> void:
	for child in mod_row.get_children():
		mod_row.remove_child(child)
		child.free()
	if preview.base_power > 0:
		mod_row.add_child(_make_modifier_chip("Base DMG: %d" % preview.base_power, UITheme.COLOR_CHIP_POWER))
	if preview.base_power > 0 and preview.weapon_mult != 1.0:
		var mult_color = UITheme.COLOR_CHIP_ADV if preview.weapon_mult > 1.0 else UITheme.COLOR_CHIP_WEAK
		var mult_tag = "ADV" if preview.weapon_mult > 1.0 else "WEAK"
		mod_row.add_child(_make_modifier_chip("×%.1f %s" % [preview.weapon_mult, mult_tag], mult_color))
	if preview.def_blocked > 0:
		mod_row.add_child(_make_modifier_chip("−%d DEF" % preview.def_blocked, UITheme.COLOR_CHIP_MITIGATE))
	if preview.cover_blocked > 0:
		mod_row.add_child(_make_modifier_chip("−%d Cover" % preview.cover_blocked, UITheme.COLOR_CHIP_MITIGATE))
	_apply_row_chip_visibility(mod_row)

func _damage_label_tweening_to(lbl: Label, to_val: int) -> bool:
	if not lbl.has_meta("dmg_tween"):
		return false
	var tw: Tween = lbl.get_meta("dmg_tween")
	if tw == null or not tw.is_valid():
		return false
	return int(lbl.get_meta("dmg_tween_target", -1)) == to_val

func _apply_row_chip_visibility(mod_row: HBoxContainer) -> void:
	var show_all := _detail_chips_visible
	for chip in mod_row.get_children():
		if chip.name == "ModChip":
			chip.visible = show_all
	mod_row.visible = show_all and mod_row.get_child_count() > 0

func _tween_heal_value(lbl: Label, from_val: int, to_val: int) -> void:
	if lbl.has_meta("dmg_tween"):
		var old_tw: Tween = lbl.get_meta("dmg_tween")
		if old_tw and old_tw.is_valid():
			old_tw.kill()
	var tw := lbl.create_tween()
	lbl.set_meta("dmg_tween", tw)
	lbl.set_meta("dmg_tween_target", to_val)
	tw.tween_method(
		func(v: float) -> void: lbl.text = "+%d HEAL" % int(v),
		float(from_val), float(to_val), 0.12)
	tw.tween_callback(func() -> void:
		lbl.set_meta("displayed_dmg", to_val)
		lbl.text = "+%d HEAL" % to_val)
	_play_value_punch(lbl)

func _tween_damage_value(lbl: Label, from_val: int, to_val: int, is_kill: bool) -> void:
	if lbl.has_meta("dmg_tween"):
		var old_tw: Tween = lbl.get_meta("dmg_tween")
		if old_tw and old_tw.is_valid():
			old_tw.kill()
	var tw := lbl.create_tween()
	lbl.set_meta("dmg_tween", tw)
	lbl.set_meta("dmg_tween_target", to_val)
	tw.tween_method(
		func(v: float) -> void: lbl.text = "%d DMG" % int(v),
		float(from_val), float(to_val), 0.12)
	tw.tween_callback(func() -> void:
		lbl.set_meta("displayed_dmg", to_val)
		lbl.text = "%d DMG" % to_val)
	_play_value_punch(lbl)
	if is_kill:
		tw.tween_callback(func() -> void: _play_kill_punch(lbl))

func _tween_damage_value_fmt(lbl: Label, from_val: int, to_val: int, use_minus_fmt: bool) -> void:
	if lbl.has_meta("dmg_tween"):
		var old_tw: Tween = lbl.get_meta("dmg_tween")
		if old_tw and old_tw.is_valid():
			old_tw.kill()
	var tw := lbl.create_tween()
	lbl.set_meta("dmg_tween", tw)
	lbl.set_meta("dmg_tween_target", to_val)
	if use_minus_fmt:
		tw.tween_method(
			func(v: float) -> void: lbl.text = "−%d" % int(v),
			float(from_val), float(to_val), 0.12)
		tw.tween_callback(func() -> void:
			lbl.set_meta("displayed_dmg", to_val)
			lbl.text = "−%d" % to_val)
	else:
		tw.tween_method(
			func(v: float) -> void: lbl.text = "%d DMG" % int(v),
			float(from_val), float(to_val), 0.12)
		tw.tween_callback(func() -> void:
			lbl.set_meta("displayed_dmg", to_val)
			lbl.text = "%d DMG" % to_val)
	_play_value_punch(lbl)

func _play_value_punch(lbl: Label) -> void:
	if lbl.has_meta("value_punch_tween"):
		var old: Tween = lbl.get_meta("value_punch_tween")
		if old and old.is_valid():
			old.kill()
	lbl.scale = Vector2.ONE
	var tw := lbl.create_tween()
	lbl.set_meta("value_punch_tween", tw)
	tw.tween_property(lbl, "scale", Vector2(1.12, 1.12), 0.06).set_trans(Tween.TRANS_BACK)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.08)

func _play_kill_punch(lbl: Label) -> void:
	if lbl.has_meta("kill_punch") and lbl.get_meta("kill_punch"):
		return
	lbl.set_meta("kill_punch", true)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "scale", Vector2(1.14, 1.14), 0.07).set_trans(Tween.TRANS_BACK)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.1)

func _play_badge_spawn(badge: Control) -> void:
	call_deferred("_play_badge_spawn_impl", badge)

func _play_badge_identity_fade(badge: Control) -> void:
	var identity := badge.find_child("IdentityRow", true, false) as CanvasItem
	if identity == null:
		return
	identity.modulate.a = 0.55
	var tw := identity.create_tween()
	tw.tween_property(identity, "modulate:a", 1.0, 0.1)

func _play_badge_spawn_impl(badge: Control) -> void:
	badge.scale = Vector2(0.94, 0.94)
	badge.modulate.a = 0.0
	var tw := badge.create_tween().set_parallel(true)
	tw.tween_property(badge, "scale", Vector2.ONE, 0.14)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(badge, "modulate:a", 1.0, 0.11)

func _update_badge_identity(badge: Control, hero: HeroUnit, skill: SkillData,
		skill_index: int, tint: Color, header: String) -> void:
	var icon := badge.find_child("SkillIcon", true, false) as TextureRect
	var name_lbl := badge.find_child("SkillName", true, false) as Label
	var atk_type_lbl := badge.find_child("AttackTypeLabel", true, false) as Label
	var hdr := badge.find_child("HeaderLabel", true, false) as Label
	var caret := badge.find_child("BadgeCaret", true, false) as Label
	var panel := badge.find_child("BadgePanel", true, false) as PanelContainer
	if icon:
		icon.texture = _skill_icon_texture(hero, skill_index, skill)
		icon.modulate = Color.WHITE
	if name_lbl:
		name_lbl.text = skill.display_name
		name_lbl.modulate = BADGE_SKILL_NAME_COLOR
	if atk_type_lbl:
		var mult = 1.0
		if badge.has_meta("last_weapon_mult"):
			mult = float(badge.get_meta("last_weapon_mult", 1.0))
		atk_type_lbl.text = _attack_type_label_text(skill, mult)
	var panel_tint = badge.get_meta("badge_panel_tint", tint) as Color
	if hdr:
		hdr.text = header
	_apply_badge_panel_styles(badge, panel_tint)
	badge.set_meta("skill", skill)
	_update_badge_effects(badge, skill)
	_play_badge_identity_fade(badge)

func get_active_skill_tint() -> Color:
	if _hero_skill_screen_popup and is_instance_valid(_hero_skill_screen_popup):
		return _hero_skill_screen_popup.get_meta("badge_panel_tint", _weapon_mult_damage_color(1.0)) as Color
	return _weapon_mult_damage_color(1.0)

const _PULSE_COLOR_ON := Color(1.45, 1.2, 0.18, 1.0)
const _PULSE_COLOR_OFF := Color.WHITE
const _PULSE_SECS := 0.72

func play_skill_selected_feedback(skill_index: int, skill: SkillData, hero: HeroUnit) -> void:
	if skill == null or hero == null or not is_instance_valid(hero):
		return
	var tint := skill.get_display_tint(skill_index)
	var btn_idx := skill_index + 1
	if btn_idx < _skill_buttons.size():
		var btn := _skill_buttons[btn_idx] as Control
		if btn:
			btn.scale = Vector2.ONE
			var tw := btn.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(btn, "scale", Vector2(1.2, 1.2), 0.1)
			tw.tween_property(btn, "scale", Vector2(1.1, 1.1), 0.14)
	if _layout_grid:
		show_unit_glows([hero], tint.lightened(0.25), _layout_grid)
		if _skill_bar_bg and is_instance_valid(_skill_bar_bg):
			_skill_bar_bg.modulate = Color(
				lerpf(1.0, tint.r, 0.35),
				lerpf(1.0, tint.g, 0.35),
				lerpf(1.0, tint.b, 0.35),
				1.0)

func apply_skill_pulse(in_range_indices: Array[int]) -> void:
	for tw in _skill_slot_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_skill_slot_tweens.clear()
	# Remove any glow overlays from previous pulse
	for btn in _skill_buttons:
		if is_instance_valid(btn):
			var old = btn.get_node_or_null("_PulseGlow")
			if old:
				old.queue_free()
			btn.modulate = Color.WHITE
	if _skill_bar_bg and is_instance_valid(_skill_bar_bg):
		_skill_bar_bg.modulate = Color.WHITE
	if _skill_buttons.is_empty():
		return
	var end_btn = _skill_buttons[0]
	if in_range_indices.is_empty():
		_add_pulse_to_button(end_btn, true)
		return
	for idx in in_range_indices:
		var btn_idx = idx + 1
		if btn_idx < _skill_buttons.size():
			_add_pulse_to_button(_skill_buttons[btn_idx], false)
	# Pulse the HUD background strip too
	if _skill_bar_bg and is_instance_valid(_skill_bar_bg):
		var bg_tw = _skill_bar_bg.create_tween().set_loops()
		bg_tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		bg_tw.tween_property(_skill_bar_bg, "modulate", Color(1.12, 1.06, 0.12, 1.0), _PULSE_SECS)
		bg_tw.tween_property(_skill_bar_bg, "modulate", Color.WHITE, _PULSE_SECS)
		_skill_slot_tweens.append(bg_tw)

func _add_pulse_to_button(btn: Control, is_end: bool) -> void:
	# Bright yellow glow overlay inside the button
	var glow = ColorRect.new()
	glow.name = "_PulseGlow"
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.color = Color(1.0, 0.85, 0.0, 0.0)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.z_index = 5
	btn.add_child(glow)
	# Tween the glow alpha
	var glow_tw = glow.create_tween().set_loops()
	glow_tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	glow_tw.tween_property(glow, "color:a", 0.42, _PULSE_SECS)
	glow_tw.tween_property(glow, "color:a", 0.0, _PULSE_SECS)
	_skill_slot_tweens.append(glow_tw)
	# Also modulate the whole button for extra pop
	var mod_tw = btn.create_tween().set_loops()
	mod_tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	mod_tw.tween_property(btn, "modulate", _PULSE_COLOR_ON, _PULSE_SECS)
	mod_tw.tween_property(btn, "modulate", _PULSE_COLOR_OFF, _PULSE_SECS)
	_skill_slot_tweens.append(mod_tw)

func hide_skill_bar() -> void:
	_clear_skill_slots()
	if _skill_bar_bg and is_instance_valid(_skill_bar_bg):
		_skill_bar_bg.modulate = Color.WHITE
	if _skill_bar_bg:
		_skill_bar_bg.visible = false
	if skill_bar:
		skill_bar.visible = false
	clear_active_skill_on_hero()

# --- Turn order ---

func show_turn_order(units: Array) -> void:
	for node in _turn_order_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_turn_order_nodes.clear()
	var count := mini(units.size(), 8)
	for i in count:
		var unit = units[i]
		if not is_instance_valid(unit) or unit.hp <= 0:
			continue
		var slot := _make_timeline_icon(unit, i == 0)
		turn_order_bar.add_child(slot)
		_turn_order_nodes.append(slot)
	call_deferred("_deferred_layout_timeline_line")

func _deferred_layout_timeline_line() -> void:
	_layout_timeline_line()
	call_deferred("_layout_timeline_line")

func _make_timeline_icon(unit: Unit, is_current: bool) -> Control:
	var slot := CenterContainer.new()
	slot.custom_minimum_size = Vector2(24, 24)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tex := TextureRect.new()
	tex.custom_minimum_size = Vector2(32, 32)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture = unit.get_body_texture()
	if tex.texture == null:
		tex.texture = Utils.sprite_frame(_default_skill_icon)
	tex.scale = Vector2(0.5, 0.5)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if unit.is_in_group("heroes"):
		tex.modulate = UITheme.HERO_ACCENT if is_current else Color(0.75, 0.95, 0.82)
	else:
		tex.modulate = UITheme.ENEMY_ACCENT if is_current else Color(0.95, 0.72, 0.68)
	slot.add_child(tex)
	if is_current:
		slot.scale = Vector2(1.12, 1.12)
	return slot

func _layout_timeline_line() -> void:
	if _timeline_line == null or _turn_order_nodes.is_empty():
		if _timeline_line:
			_timeline_line.points = PackedVector2Array()
		return
	var centers: PackedVector2Array = []
	for slot in _turn_order_nodes:
		if not is_instance_valid(slot):
			continue
		var center := slot.position + slot.size * 0.5
		centers.append(center)
	if centers.is_empty():
		_timeline_line.points = PackedVector2Array()
	elif centers.size() == 1:
		_timeline_line.points = PackedVector2Array([centers[0], centers[0]])
	else:
		_timeline_line.points = centers

func show_milestone(_text: String) -> void:
	pass

func show_turn_intent(_text: String) -> void:
	pass

func show_hero_turn() -> void:
	clear_counter_highlights()
	set_highlight_mode(HighlightMode.MOVE)

func show_enemy_turn() -> void:
	clear_skills()
	set_highlight_mode(HighlightMode.ENEMY)

func show_round(_round: int, _max_rounds: int) -> void:
	pass

func show_game_over(_victory: bool) -> void:
	clear_damage_preview()
	set_highlight_mode(HighlightMode.NONE)

func show_radial_menu(hero_world_pos: Vector2, skills: Array, states: Array) -> void:
	hide_radial_menu()
	if skills.is_empty():
		return
	var hero_screen := hero_world_pos
	if _battle:
		hero_screen = _battle.get_canvas_transform() * hero_world_pos
	var blocked := _collect_blocked_screen_rects()
	var end_pos := _place_popup_rect(Vector2(54, 24), hero_screen + Vector2(0, -RADIAL_RADIUS), blocked)
	_add_radial_node("End", end_pos, -1, -1)
	var count := skills.size()
	for i in count:
		var t := 0.5 if count == 1 else float(i) / (count - 1)
		var heading := deg_to_rad(lerp(240.0, 120.0, t))
		var offset := Vector2(sin(heading), -cos(heading)) * RADIAL_RADIUS
		var btn_pos := _place_popup_rect(Vector2(54, 24), hero_screen + offset, blocked)
		_add_radial_node(skills[i].display_name, btn_pos, i, states[i] if i < states.size() else 0)

func _add_radial_node(label_text: String, pos: Vector2, skill_index: int, state_val: int) -> void:
	var btn := Button.new()
	btn.text = label_text
	var sz := Vector2(54, 24)
	btn.custom_minimum_size = sz
	btn.size = sz
	btn.position = pos - sz / 2.0
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 11)
	match state_val:
		BattleManager.SkillState.NO_RANGE:
			btn.modulate = Color(1.0, 0.32, 0.32)
			btn.disabled = true
		BattleManager.SkillState.USED:
			btn.modulate = Color(0.42, 0.42, 0.42)
			btn.disabled = true
	var captured := skill_index
	if skill_index == -1:
		btn.pressed.connect(func(): radial_end_pressed.emit())
	else:
		btn.pressed.connect(func(): radial_skill_selected.emit(captured))
	btn.mouse_entered.connect(func(): radial_skill_hovered.emit(captured))
	btn.mouse_exited.connect(func(): radial_skill_hovered.emit(-1))
	add_child(btn)
	_radial_nodes.append(btn)

func hide_radial_menu() -> void:
	for n in _radial_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_radial_nodes.clear()
	radial_skill_hovered.emit(-1)

func clear_skills() -> void:
	hide_radial_menu()
	hide_skill_bar()

# --- Highlights ---

func show_move_highlights(tiles: Array, grid: Node) -> void:
	_free_list(_move_highlights)
	_free_list(_cover_highlights)
	_free_list(_move_outline)
	_move_positions.clear()
	for pos in tiles:
		var is_cover = grid.has_method("get_cover_bonus") and grid.get_cover_bonus(pos) > 0
		var color := UITheme.COLOR_MOVE_COVER if is_cover else UITheme.COLOR_MOVE
		var store := _cover_highlights if is_cover else _move_highlights
		_add_highlight(pos, color, store, grid, HighlightStyle.FILL)
		_move_positions.append(pos)
	if not tiles.is_empty():
		_add_range_outline(tiles, Color(0, 0, 0, 0.88), 2.0, _move_outline, grid)

func show_target_highlights(tiles: Array, grid: Node, tint: Color = UITheme.COLOR_SKILL_RANGE, attack_type: int = -1, is_heal_or_buff: bool = false) -> void:
	_free_list(_skill_range_highlights)
	_free_list(_move_skill_preview_highlights)
	_free_list(_skill_outline)
	_skill_range_positions.clear()
	var color := Color(tint.r, tint.g, tint.b, 0.20)
	for pos in tiles:
		_add_highlight(pos, color, _skill_range_highlights, grid, HighlightStyle.FILL)
		_skill_range_positions.append(pos)
	if not tiles.is_empty():
		var outline_color: Color
		if is_heal_or_buff:
			outline_color = Color(0.25, 0.85, 0.35, 0.9)
		else:
			outline_color = Color(0.9, 0.2, 0.2, 0.9)
		_add_range_outline(tiles, outline_color, 2.0, _skill_outline, grid)

func show_extended_reach_highlights(tiles: Array[Vector2i], grid: Node, is_heal: bool) -> void:
	_free_list(_extended_reach_highlights)
	if tiles.is_empty():
		return
	var fill_color = Color(0.25, 0.85, 0.35, 0.07) if is_heal else Color(0.9, 0.2, 0.2, 0.07)
	var outline_color = Color(0.25, 0.85, 0.35, 0.4) if is_heal else Color(0.9, 0.2, 0.2, 0.4)
	for pos in tiles:
		_add_highlight(pos, fill_color, _extended_reach_highlights, grid, HighlightStyle.FILL)
	_add_range_outline(tiles, outline_color, 1.5, _extended_reach_highlights, grid)

func clear_extended_reach_highlights() -> void:
	_free_list(_extended_reach_highlights)

func show_walk_to_shoot_highlights(tiles: Array[Vector2i], grid: Node) -> void:
	_free_list(_walk_to_shoot_highlights)
	for pos in tiles:
		_add_highlight(pos, Color(0.0, 0.0, 0.0, 1.0), _walk_to_shoot_highlights, grid, HighlightStyle.OUTLINE)

func clear_walk_to_shoot_highlights() -> void:
	_free_list(_walk_to_shoot_highlights)

func show_valid_target_highlights(tiles: Array, grid: Node) -> void:
	_free_list(_valid_target_highlights)
	_free_list(_kill_highlights)
	_valid_target_positions.clear()
	for pos in tiles:
		_add_highlight(pos, Color(0.0, 0.0, 0.0, 1.0), _valid_target_highlights, grid, HighlightStyle.OUTLINE)
		_valid_target_positions.append(pos)
	refresh_kill_overlays(grid)

func set_kill_targets(positions: Array) -> void:
	_kill_positions.clear()
	for pos in positions:
		_kill_positions.append(pos as Vector2i)

func refresh_kill_overlays(grid: Node) -> void:
	_free_list(_kill_highlights)
	for pos in _valid_target_positions:
		if _kill_positions.has(pos):
			_add_highlight(pos, UITheme.COLOR_KILL_TARGET, _kill_highlights, grid, HighlightStyle.FILL)

func show_cursor_aoe(tiles: Array, grid: Node, tint: Color = Color(0.95, 0.25, 0.25, 0.35)) -> void:
	_free_list(_cursor_aoe_highlights)
	for pos in tiles:
		_add_highlight(pos, tint, _cursor_aoe_highlights, grid, HighlightStyle.FILL)

func show_move_skill_preview(tiles: Array, grid: Node) -> void:
	_free_list(_move_skill_preview_highlights)
	for pos in tiles:
		_add_highlight(pos, UITheme.COLOR_SKILL_PREVIEW, _move_skill_preview_highlights, grid, HighlightStyle.FILL)

func clear_smart_attack_preview() -> void:
	for n in _smart_preview_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_smart_preview_nodes.clear()
	_clear_smart_preview_badge()
	_smart_preview_tiles.clear()

func show_smart_attack_preview(hero: HeroUnit, move_pos: Vector2i, target_pos: Vector2i,
		skill: SkillData, skill_index: int, grid: Node, kill_positions: Array,
		previews: Array = [], skip_badge: bool = false) -> void:
	for n in _smart_preview_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_smart_preview_nodes.clear()
	_smart_preview_tiles.clear()
	if hero == null or skill == null:
		_clear_smart_preview_badge()
		return
	var tint := _weapon_mult_damage_color(1.0)
	var hero_pos := hero.grid_pos
	var cast_pos := move_pos
	_smart_preview_tiles.append(cast_pos)
	_smart_preview_tiles.append(target_pos)

	if move_pos != hero_pos:
		var path := Combat.find_move_path(
			hero_pos, move_pos, grid, hero.movement_remaining + 4)
		_add_preview_path_line(path, grid, UITheme.COLOR_MOVE_PATH, 3.5, true)
		_add_highlight(move_pos, UITheme.COLOR_MOVE_DEST, _smart_preview_nodes, grid, HighlightStyle.FILL)

	var strike_pts: Array[Vector2i] = [cast_pos, target_pos]
	_add_preview_path_line(strike_pts, grid, Color(tint.r, tint.g, tint.b, 0.95), 4.5, false)

	for pos in Combat.get_skill_target_tiles(skill, cast_pos, grid):
		_add_highlight(pos, Color(tint.r, tint.g, tint.b, 0.14), _smart_preview_nodes, grid, HighlightStyle.FILL)
		_smart_preview_tiles.append(pos)

	if skill.target_type == SkillData.TargetType.ENEMY_AOE:
		for pos in grid.get_tiles_in_range(target_pos, skill.aoe_radius):
			_add_highlight(pos, Color(tint.r, tint.g, tint.b, 0.35), _smart_preview_nodes, grid, HighlightStyle.OUTLINE)
			_smart_preview_tiles.append(pos)

	var target_color := Color(tint.r, tint.g, tint.b, 0.55)
	if kill_positions.has(target_pos):
		target_color = UITheme.COLOR_KILL_TARGET
	_add_highlight(target_pos, target_color, _smart_preview_nodes, grid,
			HighlightStyle.FILL if kill_positions.has(target_pos) else HighlightStyle.OUTLINE)

	if skip_badge:
		# Direct-range cast: clear any lingering WILL USE badge, rely on ACTIVE badge
		_clear_smart_preview_badge()
		return
	var cast_key := _smart_cast_key_for(hero, cast_pos)
	if (_smart_preview_badge and is_instance_valid(_smart_preview_badge)
			and _smart_cast_key == cast_key):
		var prev_skill := int(_smart_preview_badge.get_meta("skill_index", -1))
		if prev_skill != skill_index:
			_update_badge_identity(_smart_preview_badge, hero, skill, skill_index, tint, "WILL USE")
			_smart_preview_badge.set_meta("skill_index", skill_index)
		_smart_preview_badge.set_meta("hero_grid", cast_pos)
		_update_badge_previews(_smart_preview_badge, previews)
		_position_badge_for_targets(_smart_preview_badge, target_pos)
	else:
		_clear_smart_preview_badge()
		_smart_preview_badge = _create_skill_badge(
			hero, skill, skill_index, tint, "WILL USE", previews)
		_smart_preview_badge.set_meta("skill_index", skill_index)
		_smart_preview_badge.set_meta("hero_grid", cast_pos)
		_smart_cast_key = cast_key
		if _screen_popup_layer:
			_screen_popup_layer.add_child(_smart_preview_badge)
			_position_badge_for_targets(_smart_preview_badge, target_pos)
			_play_badge_spawn(_smart_preview_badge)

func _add_preview_path_line(path: Array, grid: Node, color: Color, width: float,
		dashed: bool = false) -> void:
	if path.size() < 2:
		return
	var grid_path: Array[Vector2i] = []
	for cell in path:
		grid_path.append(cell as Vector2i)
	for i in range(grid_path.size() - 1):
		var a = grid.grid_to_world(grid_path[i])
		var b = grid.grid_to_world(grid_path[i + 1])
		if dashed:
			_add_dashed_segment(a, b, color, width, grid_path, i)
		else:
			var line := Line2D.new()
			line.points = PackedVector2Array([a, b])
			if i == 0:
				line.set_meta("grid_path", grid_path)
			line.width = width
			line.default_color = color
			line.antialiased = true
			line.z_index = 11
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
			highlight_layer.add_child(line)
			_smart_preview_nodes.append(line)

func _add_dashed_segment(a: Vector2, b: Vector2, color: Color, width: float,
		grid_path: Array[Vector2i], segment_index: int,
		dash_len: float = 7.0, gap_len: float = 5.0) -> void:
	var delta := b - a
	var length := delta.length()
	if length <= 0.01:
		return
	var dir := delta / length
	var t := 0.0
	var dash_i := 0
	while t < length:
		var seg_start := a + dir * t
		var seg_end := a + dir * minf(t + dash_len, length)
		var line := Line2D.new()
		line.points = PackedVector2Array([seg_start, seg_end])
		if segment_index == 0 and dash_i == 0:
			line.set_meta("grid_path", grid_path)
		line.width = width
		line.default_color = color
		line.antialiased = true
		line.z_index = 11
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		highlight_layer.add_child(line)
		_smart_preview_nodes.append(line)
		t += dash_len + gap_len
		dash_i += 1

func _add_smart_label(grid_pos: Vector2i, text: String, color: Color, _grid: Node) -> void:
	_add_screen_tag(grid_pos, text, color, 10)

func _add_screen_tag(grid_pos: Vector2i, text: String, color: Color, font_size: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _screen_popup_layer:
		_screen_popup_layer.add_child(lbl)
		var sz := lbl.get_minimum_size()
		lbl.position = _place_popup_near_tile(grid_pos, sz)
		_smart_preview_nodes.append(lbl)

func show_enemy_telegraph(enemy: EnemyUnit, dest: Vector2i, target: Unit, grid: Node) -> void:
	clear_enemy_telegraph()
	if dest != enemy.grid_pos:
		_add_highlight(dest, UITheme.COLOR_TELEGRAPH_MOVE, _telegraph_highlights, grid, HighlightStyle.FILL)
		_add_telegraph_intent_icon(dest, "→", Color(0.9, 0.85, 0.35), grid)
	elif is_instance_valid(target):
		_add_telegraph_intent_icon(dest, "◎", Color(0.75, 0.75, 0.8), grid)
	if is_instance_valid(target):
		_add_highlight(target.grid_pos, UITheme.COLOR_TELEGRAPH_TARGET, _telegraph_highlights, grid,
				HighlightStyle.OUTLINE)
		_add_telegraph_intent_icon(target.grid_pos, "⚔", Color(1.0, 0.35, 0.3), grid)

func _add_telegraph_intent_icon(grid_pos: Vector2i, icon_text: String, color: Color, _grid: Node) -> void:
	var lbl := Label.new()
	lbl.text = icon_text
	lbl.modulate = color
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _screen_popup_layer:
		_screen_popup_layer.add_child(lbl)
		var sz := Vector2(22, 22)
		lbl.position = _place_popup_near_tile(grid_pos, sz)
	_telegraph_highlights.append(lbl)

func clear_enemy_telegraph() -> void:
	_free_list(_telegraph_highlights)

func show_counter_highlights(heroes: Array, grid: Node) -> void:
	clear_counter_highlights()
	for hero in heroes:
		if not is_instance_valid(hero):
			continue
		var edge := UITheme.COLOR_COUNTER_EDGE
		_add_highlight(hero.grid_pos, edge, _counter_highlights, grid, HighlightStyle.OUTLINE)

func clear_counter_highlights() -> void:
	_free_list(_counter_highlights)

func show_spawn_zone_outline(tiles: Array[Vector2i], grid: Node) -> void:
	_free_list(_spawn_zone_outline)
	if not tiles.is_empty():
		_add_range_outline(tiles, Color(0.0, 0.0, 0.0, 0.88), 2.0, _spawn_zone_outline, grid)

func clear_spawn_zone_outline() -> void:
	_free_list(_spawn_zone_outline)

func set_active_actor(unit: Unit, grid: Node) -> void:
	clear_active_actor()
	_tracked_active_unit = unit
	if unit == null or not is_instance_valid(unit):
		return
	_play_turn_handoff_flash(unit.grid_pos, grid)
	var ring_color := UITheme.HERO_ACCENT if unit.is_in_group("heroes") else UITheme.ENEMY_ACCENT
	_active_actor_ring = Node2D.new()
	_active_actor_ring.z_index = 22
	_active_actor_ring.position = grid.grid_to_world(unit.grid_pos)
	highlight_layer.add_child(_active_actor_ring)
	for i in 4:
		var seg := ColorRect.new()
		seg.color = ring_color
		seg.size = Vector2(10, 3)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		match i:
			0: seg.position = Vector2(-TILE_SIZE * 0.5 + 2, -TILE_SIZE * 0.5 + 2)
			1: seg.position = Vector2(TILE_SIZE * 0.5 - 12, -TILE_SIZE * 0.5 + 2)
			2: seg.position = Vector2(-TILE_SIZE * 0.5 + 2, TILE_SIZE * 0.5 - 5)
			3: seg.position = Vector2(TILE_SIZE * 0.5 - 12, TILE_SIZE * 0.5 - 5)
		_active_actor_ring.add_child(seg)
	_active_actor_tween = _active_actor_ring.create_tween().set_loops()
	_active_actor_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_active_actor_tween.tween_property(_active_actor_ring, "scale", Vector2(1.14, 1.14), 0.32)
	_active_actor_tween.tween_property(_active_actor_ring, "scale", Vector2(1.0, 1.0), 0.32)

func _play_turn_handoff_flash(grid_pos: Vector2i, grid: Node) -> void:
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.45)
	flash.size = Vector2(TILE_SIZE, TILE_SIZE)
	flash.position = grid.grid_to_world(grid_pos) - Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 21
	highlight_layer.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.14)
	tw.finished.connect(flash.queue_free)

func clear_active_actor() -> void:
	_tracked_active_unit = null
	if _active_actor_tween and is_instance_valid(_active_actor_tween):
		_active_actor_tween.kill()
	_active_actor_tween = null
	if _active_actor_ring and is_instance_valid(_active_actor_ring):
		_active_actor_ring.queue_free()
	_active_actor_ring = null

func update_active_actor_position(unit: Unit, grid: Node) -> void:
	if unit == _tracked_active_unit:
		_tracked_active_unit = unit
	if _active_actor_ring and is_instance_valid(_active_actor_ring) and unit:
		_active_actor_ring.position = grid.grid_to_world(unit.grid_pos)

func show_unit_glows(units: Array, glow_color: Color, grid: Node) -> void:
	clear_unit_glows()
	for unit in units:
		if not is_instance_valid(unit) or unit.hp <= 0:
			continue
		var color := Color(glow_color.r, glow_color.g, glow_color.b, 0.92)
		_add_highlight(unit.grid_pos, color, _unit_glow_highlights, grid, HighlightStyle.OUTLINE)
		_add_highlight(unit.grid_pos, Color(glow_color.r, glow_color.g, glow_color.b, 0.18),
				_unit_glow_highlights, grid, HighlightStyle.FILL)

func clear_unit_glows() -> void:
	_free_list(_unit_glow_highlights)

func spawn_move_dust(grid_pos: Vector2i, grid: Node, unit_color: Color = Color(0.5, 0.85, 1.0, 0.45)) -> void:
	if highlight_layer == null:
		return
	Utils.spawn_move_dust(grid.grid_to_world(grid_pos), highlight_layer, unit_color)

func play_damage_vignette(tier: int, is_hero_attack: bool = false) -> void:
	if _screen_popup_layer == null:
		return
	var strength: float
	if is_hero_attack:
		strength = clampf(float(tier) / 3.0, 0.14, 0.38)
	else:
		strength = clampf(float(tier - 1) / 2.0, 0.15, 0.42)
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.offset_right = 0.0
	vignette.offset_bottom = 0.0
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_hero_attack:
		vignette.color = Color(0.04, 0.42, 0.16, strength)
	else:
		vignette.color = Color(0.45, 0.02, 0.05, strength)
	vignette.modulate = Color(1, 1, 1, 1)
	_screen_popup_layer.add_child(vignette)
	_screen_popup_layer.move_child(vignette, 0)
	var tw := vignette.create_tween()
	tw.tween_property(vignette, "modulate:a", 0.0, 0.38)
	tw.finished.connect(vignette.queue_free)

func spawn_move_ghost(grid_pos: Vector2i, grid: Node, unit_color: Color = Color(0.5, 0.85, 1.0, 0.45)) -> void:
	var ghost := ColorRect.new()
	ghost.color = unit_color
	ghost.size = Vector2(TILE_SIZE - 4, TILE_SIZE - 4)
	ghost.position = grid.grid_to_world(grid_pos) - Vector2(TILE_SIZE / 2.0 - 2, TILE_SIZE / 2.0 - 2)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = 3
	highlight_layer.add_child(ghost)
	_move_ghosts.append(ghost)
	var tween := ghost.create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(ghost, "modulate:a", 0.0, 0.28)
	tween.finished.connect(func():
		if is_instance_valid(ghost):
			ghost.queue_free()
		_move_ghosts.erase(ghost)
	)

func play_kill_flash(grid_pos: Vector2i, grid: Node) -> Signal:
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.15, 0.15, 0.85)
	flash.size = Vector2(TILE_SIZE, TILE_SIZE)
	flash.position = grid.grid_to_world(grid_pos) - Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 18
	highlight_layer.add_child(flash)
	var skull := Label.new()
	skull.text = "KILL"
	Utils.apply_floating_label_style(skull, 16)
	skull.modulate = Color(1, 0.95, 0.2)
	skull.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _screen_popup_layer:
		_screen_popup_layer.add_child(skull)
		skull.position = _place_popup_near_tile(grid_pos, Vector2(28, 28))
	var tween := flash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "modulate:a", 0.0, 0.28)
	if is_instance_valid(skull):
		var skull_start := skull.position.y
		tween.tween_property(skull, "position:y", skull_start - 18, 0.28)
		tween.tween_property(skull, "modulate:a", 0.0, 0.28)
	tween.finished.connect(func():
		if is_instance_valid(flash): flash.queue_free()
		if is_instance_valid(skull): skull.queue_free()
	)
	return tween.finished

func show_status_indicators(_counter_heroes: Array, linked_pairs: Array, grid: Node) -> void:
	_free_list(_status_icons)
	for pair in linked_pairs:
		if pair.size() < 2:
			continue
		for hero in pair:
			if is_instance_valid(hero):
				_add_status_icon(hero, "LNK", Color(0.5, 0.85, 1.0), grid)

func _add_status_icon(unit: Node, icon_text: String, color: Color, _grid: Node) -> void:
	if not unit is Unit:
		return
	var lbl := Label.new()
	lbl.text = icon_text
	lbl.modulate = color
	Utils.apply_floating_label_style(lbl, 10)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _screen_popup_layer:
		_screen_popup_layer.add_child(lbl)
		lbl.position = _place_popup_near_tile(unit.grid_pos, Vector2(20, 18))
	_status_icons.append(lbl)

func clear_highlights() -> void:
	_free_list(_move_highlights)
	_free_list(_move_outline)
	_free_list(_skill_range_highlights)
	_free_list(_skill_outline)
	_free_list(_valid_target_highlights)
	_free_list(_cursor_aoe_highlights)
	_free_list(_move_skill_preview_highlights)
	_free_list(_cover_highlights)
	_free_list(_kill_highlights)
	clear_enemy_telegraph()
	clear_active_skill_on_hero()
	clear_active_actor()
	clear_counter_highlights()
	clear_smart_attack_preview()
	clear_unit_glows()
	clear_spawn_zone_outline()
	clear_walk_to_shoot_highlights()
	clear_extended_reach_highlights()
	_move_positions.clear()
	_skill_range_positions.clear()
	_valid_target_positions.clear()
	_kill_positions.clear()
	clear_damage_preview()
	_highlight_mode = HighlightMode.NONE

# --- Damage preview ---

func show_damage_preview(text: String) -> void:
	if _preview_label:
		_preview_label.text = text
		call_deferred("_layout_damage_preview")

func clear_damage_preview() -> void:
	if _preview_label:
		_preview_label.text = ""

# --- Hover outline ---

func update_hover(grid_pos: Vector2i, grid: Node) -> void:
	if not _is_interactable(grid_pos):
		hide_hover()
		return
	if _hover_panel == null:
		_hover_panel = Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = UITheme.COLOR_HOVER_OUTLINE
		style.set_border_width_all(2)
		style.draw_center = false
		_hover_panel.add_theme_stylebox_override("panel", style)
		_hover_panel.size = Vector2(TILE_SIZE, TILE_SIZE)
		_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hover_panel.z_index = 10
		highlight_layer.add_child(_hover_panel)
	_hover_panel.position = grid.grid_to_world(grid_pos) - Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	_hover_panel.visible = true

func hide_hover() -> void:
	if _hover_panel:
		_hover_panel.visible = false

func _is_interactable(pos: Vector2i) -> bool:
	return (_move_positions.has(pos) or _skill_range_positions.has(pos)
		or _valid_target_positions.has(pos))

func _add_highlight(grid_pos: Vector2i, color: Color, store: Array, grid: Node,
		style: HighlightStyle = HighlightStyle.FILL) -> void:
	var world_pos = grid.grid_to_world(grid_pos) - Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	if style == HighlightStyle.OUTLINE:
		var panel := Panel.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.border_color = color
		box.set_border_width_all(2)
		box.draw_center = false
		panel.add_theme_stylebox_override("panel", box)
		panel.size = Vector2(TILE_SIZE, TILE_SIZE)
		panel.position = world_pos
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		highlight_layer.add_child(panel)
		store.append(panel)
	else:
		var rect := ColorRect.new()
		rect.color = color
		rect.size = Vector2(TILE_SIZE, TILE_SIZE)
		rect.position = world_pos
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		highlight_layer.add_child(rect)
		store.append(rect)

func _free_list(store: Array) -> void:
	for h in store:
		if is_instance_valid(h):
			h.queue_free()
	store.clear()

# --- Range perimeter outline ---

func _add_range_outline(tiles: Array, color: Color, thickness: float, store: Array, grid: Node) -> void:
	var tile_set: Dictionary = {}
	for pos in tiles:
		tile_set[pos] = true
	var half = TILE_SIZE * 0.5
	for pos in tiles:
		var world_center = grid.grid_to_world(pos)
		if not tile_set.has(Vector2i(pos.x, pos.y - 1)):
			_add_range_line(world_center + Vector2(-half, -half),
				world_center + Vector2(half, -half), color, thickness, store)
		if not tile_set.has(Vector2i(pos.x, pos.y + 1)):
			_add_range_line(world_center + Vector2(-half, half),
				world_center + Vector2(half, half), color, thickness, store)
		if not tile_set.has(Vector2i(pos.x - 1, pos.y)):
			_add_range_line(world_center + Vector2(-half, -half),
				world_center + Vector2(-half, half), color, thickness, store)
		if not tile_set.has(Vector2i(pos.x + 1, pos.y)):
			_add_range_line(world_center + Vector2(half, -half),
				world_center + Vector2(half, half), color, thickness, store)

func _add_range_line(a: Vector2, b: Vector2, color: Color, thickness: float, store: Array) -> void:
	var line = Line2D.new()
	line.points = PackedVector2Array([a, b])
	line.default_color = color
	line.width = thickness
	line.antialiased = false
	line.z_index = 5
	highlight_layer.add_child(line)
	store.append(line)

# --- Skill type string ---

func _attack_type_outline_color(atype: int) -> Color:
	match atype:
		WeaponTriangle.Type.RANGE:
			return Color(0.25, 0.85, 0.35, 0.9)
		WeaponTriangle.Type.MAGE:
			return Color(0.3, 0.5, 1.0, 0.9)
		WeaponTriangle.Type.MELEE:
			return Color(0.9, 0.2, 0.2, 0.9)
		_:
			return Color(0, 0, 0, 0.88)

func _create_weakness_panel() -> Control:
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UITheme.badge_panel_style(Color(0.55, 0.58, 0.72)))
	var col = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 5)
	panel.add_child(col)
	col.add_child(_make_badge_separator())
	var title = Label.new()
	title.text = "Damage Advantages"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UITheme.FONT_XS)
	title.modulate = BADGE_SKILL_NAME_COLOR
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)
	col.add_child(_make_badge_separator())
	var matchups = [
		["Mage", "Melee", Color(0.3, 0.5, 1.0), Color(0.9, 0.2, 0.2)],
		["Melee", "Range", Color(0.9, 0.2, 0.2), Color(0.25, 0.85, 0.35)],
		["Range", "Mage", Color(0.25, 0.85, 0.35), Color(0.3, 0.5, 1.0)],
	]
	for m in matchups:
		var row = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 5)
		col.add_child(row)
		row.add_child(_make_modifier_chip(m[0] as String, m[2] as Color))
		var arrow = Label.new()
		arrow.text = ">"
		arrow.add_theme_font_size_override("font_size", UITheme.FONT_XS)
		arrow.modulate = BADGE_SKILL_NAME_COLOR
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(arrow)
		row.add_child(_make_modifier_chip(m[1] as String, m[3] as Color))
	return panel

func _get_skill_type_string(skill: SkillData) -> String:
	if skill == null:
		return ""
	if skill.is_healing():
		return "Heal"
	if skill.target_type == SkillData.TargetType.SELF:
		return "Self Buff"
	if skill.target_type == SkillData.TargetType.ALLY_SINGLE and skill.base_damage <= 0:
		return "Support"
	match skill.attack_type_override:
		WeaponTriangle.Type.MAGE:
			return "Mage"
		WeaponTriangle.Type.RANGE:
			return "Ranged"
		_:
			return "Melee"

func _attack_type_label_text(skill: SkillData, weapon_mult: float = 1.0) -> String:
	if skill == null:
		return ""
	var base := _get_skill_type_string(skill)
	if skill.is_healing() or skill.is_buff():
		return base
	if weapon_mult > 1.0:
		return "%s (Advantage)" % base
	if weapon_mult < 1.0:
		return "%s (Weakened)" % base
	return base

func _update_attack_type_label(badge: Control, skill: SkillData, weapon_mult: float) -> void:
	var atk_type_lbl = badge.find_child("AttackTypeLabel", true, false) as Label
	if atk_type_lbl == null or skill == null:
		return
	atk_type_lbl.text = _attack_type_label_text(skill, weapon_mult)

# --- Buff/debuff effects in badge ---

func _update_badge_effects(badge: Control, skill: SkillData) -> void:
	var eff_list = BuffDebuff.get_effects_for_skill(skill) if skill != null else []
	var tint = badge.get_meta("badge_panel_tint", _weapon_mult_damage_color(1.0)) as Color
	var skill_id: StringName = skill.id if skill != null else &""
	var last_skill: StringName = badge.get_meta("effects_panel_skill", &"") as StringName
	if last_skill == skill_id and _effects_desc_panel and is_instance_valid(_effects_desc_panel):
		_sync_effects_panel_tint(tint)
		return
	badge.set_meta("effects_panel_skill", skill_id)
	_rebuild_effects_desc_panel(eff_list, tint)

func _free_effects_desc_panel() -> void:
	if _effects_desc_panel and is_instance_valid(_effects_desc_panel):
		_effects_desc_panel.queue_free()
	_effects_desc_panel = null

func _rebuild_effects_desc_panel(eff_list: Array, tint: Color) -> void:
	_free_effects_desc_panel()
	if eff_list.is_empty():
		return
	_effects_desc_panel = _create_effects_desc_panel(eff_list, tint)
	if _screen_popup_layer and _effects_desc_panel:
		_screen_popup_layer.add_child(_effects_desc_panel)
		_relayout_effects_panel()

func _create_effects_desc_panel(eff_list: Array, tint: Color) -> Control:
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.clip_contents = false
	panel.custom_minimum_size = Vector2(148, 0)
	panel.add_theme_stylebox_override("panel", UITheme.badge_panel_style(tint))

	var col = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	col.add_child(_make_badge_separator())

	var title = Label.new()
	title.text = "STATUS EFFECTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UITheme.FONT_XS)
	title.modulate = BADGE_SKILL_NAME_COLOR
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)

	col.add_child(_make_badge_separator())

	var detail_labels: Array[Label] = []
	for eff in eff_list:
		var eff_data = eff as StatusEffectData
		if eff_data == null:
			continue
		var tag_row = HBoxContainer.new()
		tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_row.add_theme_constant_override("separation", 4)
		col.add_child(tag_row)
		tag_row.add_child(_make_modifier_chip(eff_data.display_name, eff_data.color))
		var dur_lbl = Label.new()
		dur_lbl.text = "%d turns" % eff_data.duration
		dur_lbl.add_theme_font_size_override("font_size", UITheme.FONT_XS)
		dur_lbl.modulate = BADGE_SKILL_NAME_COLOR
		dur_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dur_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dur_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_row.add_child(dur_lbl)
		var target_lbl = Label.new()
		target_lbl.name = "EffectTarget"
		target_lbl.text = "Enemy" if eff_data.is_debuff else "Self"
		target_lbl.add_theme_font_size_override("font_size", UITheme.FONT_XS)
		target_lbl.modulate = UITheme.ENEMY_ACCENT if eff_data.is_debuff else UITheme.HERO_ACCENT
		target_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(target_lbl)
		var desc_lbl = Label.new()
		desc_lbl.name = "EffectDetail_%s" % eff_data.id
		desc_lbl.text = eff_data.get_detail_text()
		desc_lbl.add_theme_font_size_override("font_size", UITheme.FONT_XS)
		desc_lbl.modulate = BADGE_SKILL_NAME_COLOR
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_lbl.custom_minimum_size = Vector2(130, 0)
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc_lbl.visible = _detail_chips_visible
		col.add_child(desc_lbl)
		detail_labels.append(desc_lbl)
		col.add_child(_make_badge_separator())

	panel.set_meta("effect_detail_labels", detail_labels)
	return panel

func _relayout_effects_panel() -> void:
	if _effects_desc_panel == null or not is_instance_valid(_effects_desc_panel):
		return
	var badge: Control = null
	if _hero_skill_screen_popup and is_instance_valid(_hero_skill_screen_popup):
		badge = _hero_skill_screen_popup
	elif _smart_preview_badge and is_instance_valid(_smart_preview_badge):
		badge = _smart_preview_badge
	if badge == null:
		return
	_layout_attack_popups(badge)
