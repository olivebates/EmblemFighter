class_name BattleHUD
extends CanvasLayer

signal radial_skill_selected(index: int)
signal radial_end_pressed
signal radial_skill_hovered(index: int)
signal skill_bar_selected(index: int)
signal skill_bar_end_pressed

@onready var skill_bar: HBoxContainer = $SkillBar
@onready var highlight_layer: Node2D = $HighlightLayer
@onready var turn_order_bar: HBoxContainer = $TopChrome/TimelineRoot/TurnOrderBar
@onready var _top_chrome: Control = $TopChrome
@onready var _timeline_root: Control = $TopChrome/TimelineRoot
@onready var _timeline_line: Line2D = $TopChrome/TimelineRoot/TimelineLine

var _skill_buttons: Array[Control] = []
var _skill_slot_tweens: Array[Tween] = []
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

var _hover_panel: Panel = null

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

func set_highlight_mode(mode: HighlightMode) -> void:
	if _highlight_mode == mode:
		return
	_highlight_mode = mode
	if mode != HighlightMode.MOVE:
		_free_list(_move_highlights)
		_free_list(_cover_highlights)
		_move_positions.clear()
	if mode != HighlightMode.SKILL:
		_free_list(_skill_range_highlights)
		_free_list(_valid_target_highlights)
		_free_list(_cursor_aoe_highlights)
		_free_list(_move_skill_preview_highlights)
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

func _relayout_skill_badges() -> void:
	if (_hero_skill_screen_popup and is_instance_valid(_hero_skill_screen_popup)
			and _popup_anchor_unit and is_instance_valid(_popup_anchor_unit)):
		var fallback: Vector2i = _hero_skill_screen_popup.get_meta(
			"badge_fallback_grid", _popup_anchor_unit.grid_pos)
		_position_skill_badge(_hero_skill_screen_popup, fallback)
	if _smart_preview_badge and is_instance_valid(_smart_preview_badge):
		var fallback: Vector2i = _smart_preview_badge.get_meta(
			"badge_fallback_grid", Vector2i(-999, -999))
		if fallback != Vector2i(-999, -999):
			_position_skill_badge(_smart_preview_badge, fallback)

func _place_popup_near_tile(grid_pos: Vector2i, popup_size: Vector2) -> Vector2:
	return _place_skill_badge(grid_pos, popup_size)

func _measure_control(ctrl: Control) -> Vector2:
	if ctrl == null:
		return Vector2.ZERO
	return ctrl.get_combined_minimum_size()

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
		return

	var end_btn := Button.new()
	end_btn.text = "End"
	end_btn.custom_minimum_size = Vector2(44, 44)
	end_btn.add_theme_font_size_override("font_size", UITheme.FONT_MD)
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

func _make_skill_icon_slot(hero: HeroUnit, skill_index: int, skill: SkillData,
		state_val: int, is_active: bool) -> Control:
	var tint := skill.get_display_tint(skill_index)
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(44, 44)
	wrapper.tooltip_text = skill.display_name

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", UITheme.tinted_panel_style(tint, is_active))
	wrapper.add_child(panel)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)

	var tex := TextureRect.new()
	tex.custom_minimum_size = Vector2(32, 32)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture = _skill_icon_texture(hero, skill_index, skill)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match state_val:
		BattleManager.SkillState.NO_RANGE:
			tex.modulate = Color(0.55, 0.55, 0.55, 0.65)
		BattleManager.SkillState.USED:
			tex.modulate = Color(0.35, 0.35, 0.35, 0.45)
		_:
			tex.modulate = tint if not is_active else tint.lightened(0.2)
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
	elif state_val == BattleManager.SkillState.NO_RANGE:
		var slash := ColorRect.new()
		slash.color = Color(0.95, 0.25, 0.25, 0.75)
		slash.size = Vector2(2, 42)
		slash.pivot_offset = slash.size * 0.5
		slash.position = Vector2(21, 1)
		slash.rotation = deg_to_rad(45)
		slash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(slash)

	if is_active:
		var glow := panel.create_tween().set_loops()
		glow.tween_property(panel, "modulate", Color(1.12, 1.12, 1.12, 1.0), 0.45)
		glow.tween_property(panel, "modulate", Color.WHITE, 0.45)
		_skill_slot_tweens.append(glow)

	return wrapper

# --- In-world active skill indicator ---

func show_active_skill_on_hero(hero: HeroUnit, skill: SkillData, skill_index: int, _grid: Node,
		previews: Array = []) -> void:
	if hero == null or skill == null:
		clear_active_skill_on_hero()
		return
	if skill_index < 0:
		skill_index = hero.skills.find(skill)
	var tint := skill.get_display_tint(skill_index)
	if (_hero_skill_screen_popup and is_instance_valid(_hero_skill_screen_popup)
			and _popup_anchor_unit == hero):
		_active_skill = skill
		_active_skill_index = skill_index
		_update_badge_identity(_hero_skill_screen_popup, hero, skill, skill_index, tint, "ACTIVE")
		_update_badge_previews(_hero_skill_screen_popup, previews)
		_position_skill_badge(_hero_skill_screen_popup, hero.grid_pos)
		return
	clear_active_skill_on_hero()
	_active_skill = skill
	_active_skill_index = skill_index
	_popup_anchor_unit = hero
	_hero_skill_screen_popup = _create_skill_badge(
		hero, skill, skill_index, tint, "ACTIVE", previews)
	if _screen_popup_layer:
		_screen_popup_layer.add_child(_hero_skill_screen_popup)
		_position_skill_badge(_hero_skill_screen_popup, hero.grid_pos)
		_play_badge_spawn(_hero_skill_screen_popup)

func update_active_skill_badge_damage(previews: Array) -> void:
	if _hero_skill_screen_popup == null or not is_instance_valid(_hero_skill_screen_popup):
		return
	_update_badge_previews(_hero_skill_screen_popup, previews)
	_position_skill_badge(_hero_skill_screen_popup, _popup_anchor_unit.grid_pos)

func clear_active_skill_on_hero() -> void:
	if _hero_skill_screen_popup and is_instance_valid(_hero_skill_screen_popup):
		_hero_skill_screen_popup.queue_free()
	_hero_skill_screen_popup = null
	_popup_anchor_unit = null
	_active_skill = null
	_active_skill_index = -1

func _clear_smart_preview_badge() -> void:
	if _smart_preview_badge and is_instance_valid(_smart_preview_badge):
		_smart_preview_badge.queue_free()
	_smart_preview_badge = null
	_smart_cast_key = ""

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
	tex.modulate = tint
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(tex)

	var name_lbl := Label.new()
	name_lbl.name = "SkillName"
	name_lbl.text = skill.display_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_MD)
	name_lbl.modulate = tint.lightened(0.15)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(name_lbl)

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
			hint.visible = not _detail_chips_visible
		var target_rows := badge.find_child("TargetRows", true, false) as VBoxContainer
		if target_rows == null:
			continue
		for row in target_rows.get_children():
			_refresh_row_chip_visibility(row as VBoxContainer)

func _refresh_row_chip_visibility(row: VBoxContainer) -> void:
	if row == null:
		return
	var mod_row := row.find_child("ModRow", true, false) as HBoxContainer
	var dmg_lbl := row.find_child("DamageValue", true, false) as Label
	if mod_row == null:
		return
	var is_kill = dmg_lbl != null and dmg_lbl.get_meta("is_kill", false)
	var show_all := _should_show_modifier_chips(is_kill)
	for chip in mod_row.get_children():
		if chip.name == "ModChip":
			var chip_text := (chip.get_child(0) as Label).text if chip.get_child_count() > 0 else ""
			if chip_text.contains("KILL"):
				chip.visible = true
			else:
				chip.visible = show_all
	mod_row.visible = mod_row.get_child_count() > 0 and (
		is_kill or show_all or _row_has_visible_chip(mod_row))

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

	var header_row := HBoxContainer.new()
	header_row.name = "HeaderRow"
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(header_row)

	var name_lbl := Label.new()
	name_lbl.name = "TargetName"
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.modulate = Color(0.88, 0.89, 0.94)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(name_lbl)

	var dmg_lbl := Label.new()
	dmg_lbl.name = "DamageValue"
	dmg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dmg_lbl.add_theme_font_size_override("font_size", 20)
	dmg_lbl.modulate = UITheme.COLOR_DAMAGE_NORMAL
	dmg_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dmg_lbl.set_meta("displayed_dmg", -1)
	header_row.add_child(dmg_lbl)

	var mod_row := HBoxContainer.new()
	mod_row.name = "ModRow"
	mod_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mod_row.add_theme_constant_override("separation", 4)
	row.add_child(mod_row)

	return row

func _update_badge_previews(badge: Control, previews: Array) -> void:
	var dmg_box := badge.find_child("DamageBreakdown", true, false) as VBoxContainer
	var dmg_sep := badge.find_child("DamageSeparator", true, false) as CanvasItem
	if dmg_box == null:
		return
	var target_rows := dmg_box.find_child("TargetRows", true, false) as VBoxContainer
	var total_row := dmg_box.find_child("TotalRow", true, false) as CanvasItem
	var total_dmg := dmg_box.find_child("TotalDamage", true, false) as Label
	if previews.is_empty():
		dmg_box.visible = false
		if dmg_sep:
			dmg_sep.visible = false
		return
	dmg_box.visible = true
	if dmg_sep:
		dmg_sep.visible = true
	var show_names := previews.size() > 1
	_ensure_target_rows(target_rows, previews.size())
	var total := 0
	var is_heal = previews[0].get("is_heal", false)
	for i in previews.size():
		_update_target_row(target_rows.get_child(i) as VBoxContainer, previews[i], show_names)
		if is_heal:
			total += previews[i].get("actual_heal", previews[i].get("heal", 0))
		else:
			total += previews[i].dmg
	if previews.size() > 1:
		total_row.visible = true
		if total_dmg:
			total_dmg.text = ("+%d HEAL" % total) if is_heal else ("%d DMG" % total)
			total_dmg.modulate = UITheme.COLOR_HEAL if is_heal else Color(0.95, 0.88, 0.55)
	else:
		total_row.visible = false

func _update_target_row(row: VBoxContainer, preview: Dictionary, show_name: bool) -> void:
	var header_row := row.find_child("HeaderRow", true, false) as HBoxContainer
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
		dmg_lbl.add_theme_font_size_override("font_size", 20)
	else:
		dmg_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dmg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dmg_lbl.add_theme_font_size_override("font_size", 22)

	var is_heal: bool = preview.get("is_heal", false)
	if is_heal:
		var heal_amt: int = preview.get("heal", 0)
		var actual: int = preview.get("actual_heal", heal_amt)
		var new_val: int = actual
		var old_val: int = int(dmg_lbl.get_meta("displayed_dmg", -1))
		dmg_lbl.modulate = UITheme.COLOR_HEAL
		dmg_lbl.set_meta("is_kill", false)
		var label := "+%d HEAL" % actual
		if actual < heal_amt:
			label = "+%d HEAL" % actual
		if old_val != new_val:
			if old_val < 0:
				dmg_lbl.text = label
				dmg_lbl.set_meta("displayed_dmg", new_val)
			else:
				_tween_heal_value(dmg_lbl, old_val, new_val)
		else:
			dmg_lbl.text = label
		for child in mod_row.get_children():
			child.queue_free()
		mod_row.add_child(_make_modifier_chip("%d HP" % heal_amt, UITheme.COLOR_HEAL))
		if actual < heal_amt:
			mod_row.add_child(_make_modifier_chip("capped", UITheme.COLOR_CHIP_MITIGATE))
		_apply_row_chip_visibility(mod_row, false)
		return

	var is_kill: bool = preview.is_kill
	var new_dmg: int = preview.dmg
	var old_dmg: int = int(dmg_lbl.get_meta("displayed_dmg", -1))
	dmg_lbl.set_meta("is_kill", is_kill)
	if not is_kill:
		dmg_lbl.set_meta("kill_punch", false)
	dmg_lbl.modulate = UITheme.COLOR_DAMAGE_KILL if is_kill else UITheme.COLOR_DAMAGE_NORMAL

	if old_dmg != new_dmg:
		if old_dmg < 0:
			dmg_lbl.text = "%d DMG" % new_dmg
			dmg_lbl.set_meta("displayed_dmg", new_dmg)
			if is_kill:
				_play_kill_punch(dmg_lbl)
			else:
				_play_value_punch(dmg_lbl)
		else:
			_tween_damage_value(dmg_lbl, old_dmg, new_dmg, is_kill)
	else:
		dmg_lbl.text = "%d DMG" % new_dmg

	for child in mod_row.get_children():
		child.queue_free()
	if preview.base_power > 0 and preview.weapon_mult != 1.0:
		mod_row.add_child(_make_modifier_chip(str(preview.base_power), UITheme.COLOR_CHIP_POWER))
		var mult_color := UITheme.COLOR_CHIP_ADV if preview.weapon_mult > 1.0 else UITheme.COLOR_CHIP_WEAK
		var mult_tag := "ADV" if preview.weapon_mult > 1.0 else "WEAK"
		mod_row.add_child(_make_modifier_chip("×%.1f %s" % [preview.weapon_mult, mult_tag], mult_color))
	elif preview.base_power > 0:
		mod_row.add_child(_make_modifier_chip(str(preview.base_power), UITheme.COLOR_CHIP_POWER))
	if preview.def_blocked > 0:
		mod_row.add_child(_make_modifier_chip("−%d DEF" % preview.def_blocked, UITheme.COLOR_CHIP_MITIGATE))
	if preview.cover_blocked > 0:
		mod_row.add_child(_make_modifier_chip("−%d Cover" % preview.cover_blocked, UITheme.COLOR_CHIP_MITIGATE))
	if is_kill:
		mod_row.add_child(_make_modifier_chip("☠ KILL", UITheme.COLOR_DAMAGE_KILL))
	_apply_row_chip_visibility(mod_row, is_kill)

func _apply_row_chip_visibility(mod_row: HBoxContainer, is_kill: bool) -> void:
	var show_all := _should_show_modifier_chips(is_kill)
	for chip in mod_row.get_children():
		if chip.name != "ModChip":
			continue
		var chip_text := (chip.get_child(0) as Label).text if chip.get_child_count() > 0 else ""
		chip.visible = chip_text.contains("KILL") or show_all
	mod_row.visible = mod_row.get_child_count() > 0 and (
		is_kill or show_all or _row_has_visible_chip(mod_row))

func _tween_heal_value(lbl: Label, from_val: int, to_val: int) -> void:
	if lbl.has_meta("dmg_tween"):
		var old_tw: Tween = lbl.get_meta("dmg_tween")
		if old_tw and old_tw.is_valid():
			old_tw.kill()
	var tw := lbl.create_tween()
	lbl.set_meta("dmg_tween", tw)
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
	tw.tween_method(
		func(v: float) -> void: lbl.text = "%d DMG" % int(v),
		float(from_val), float(to_val), 0.12)
	tw.tween_callback(func() -> void:
		lbl.set_meta("displayed_dmg", to_val)
		lbl.text = "%d DMG" % to_val)
	_play_value_punch(lbl)
	if is_kill:
		tw.tween_callback(func() -> void: _play_kill_punch(lbl))

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
	var hdr := badge.find_child("HeaderLabel", true, false) as Label
	var caret := badge.find_child("BadgeCaret", true, false) as Label
	var panel := badge.find_child("BadgePanel", true, false) as PanelContainer
	if icon:
		icon.texture = _skill_icon_texture(hero, skill_index, skill)
		icon.modulate = tint
	if name_lbl:
		name_lbl.text = skill.display_name
		name_lbl.modulate = tint.lightened(0.15)
	if hdr:
		hdr.text = header
	if caret:
		caret.modulate = Color(tint.r, tint.g, tint.b, 0.8)
	if panel:
		panel.add_theme_stylebox_override("panel", UITheme.badge_panel_style(tint))
	if hdr:
		var header_strip := hdr.get_parent() as PanelContainer
		if header_strip:
			header_strip.add_theme_stylebox_override("panel", UITheme.badge_header_style(tint, header))
	_play_badge_identity_fade(badge)

func get_active_skill_tint() -> Color:
	if _active_skill and _active_skill_index >= 0:
		return _active_skill.get_display_tint(_active_skill_index)
	return UITheme.COLOR_SKILL_RANGE

func hide_skill_bar() -> void:
	for btn in _skill_buttons:
		btn.queue_free()
	_skill_buttons.clear()
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
	_move_positions.clear()
	for pos in tiles:
		var is_cover = grid.has_method("get_cover_bonus") and grid.get_cover_bonus(pos) > 0
		var color := UITheme.COLOR_MOVE_COVER if is_cover else UITheme.COLOR_MOVE
		var store := _cover_highlights if is_cover else _move_highlights
		_add_highlight(pos, color, store, grid, HighlightStyle.FILL)
		_move_positions.append(pos)

func show_target_highlights(tiles: Array, grid: Node, tint: Color = UITheme.COLOR_SKILL_RANGE) -> void:
	_free_list(_skill_range_highlights)
	_free_list(_move_skill_preview_highlights)
	_skill_range_positions.clear()
	var color := Color(tint.r, tint.g, tint.b, 0.20)
	for pos in tiles:
		_add_highlight(pos, color, _skill_range_highlights, grid, HighlightStyle.FILL)
		_skill_range_positions.append(pos)

func show_valid_target_highlights(tiles: Array, grid: Node) -> void:
	_free_list(_valid_target_highlights)
	_free_list(_kill_highlights)
	_valid_target_positions.clear()
	for pos in tiles:
		_add_highlight(pos, UITheme.COLOR_VALID_TARGET, _valid_target_highlights, grid, HighlightStyle.OUTLINE)
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
		previews: Array = []) -> void:
	for n in _smart_preview_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_smart_preview_nodes.clear()
	_smart_preview_tiles.clear()
	if hero == null or skill == null:
		_clear_smart_preview_badge()
		return
	var tint := skill.get_display_tint(skill_index)
	var hero_pos := hero.grid_pos
	var cast_pos := move_pos
	_smart_preview_tiles.append(cast_pos)
	_smart_preview_tiles.append(target_pos)

	if move_pos != hero_pos:
		var path := Combat.find_move_path(
			hero_pos, move_pos, grid, hero.movement_remaining + 4)
		_add_preview_path_line(path, grid, UITheme.COLOR_MOVE_PATH, 3.5, true)
		_add_highlight(move_pos, UITheme.COLOR_MOVE_DEST, _smart_preview_nodes, grid, HighlightStyle.FILL)
		_add_smart_label(move_pos, "MOVE", UITheme.COLOR_MOVE_PATH, grid)

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

	var cast_key := _smart_cast_key_for(hero, cast_pos)
	if (_smart_preview_badge and is_instance_valid(_smart_preview_badge)
			and _smart_cast_key == cast_key):
		var prev_skill := int(_smart_preview_badge.get_meta("skill_index", -1))
		if prev_skill != skill_index:
			_update_badge_identity(_smart_preview_badge, hero, skill, skill_index, tint, "WILL USE")
			_smart_preview_badge.set_meta("skill_index", skill_index)
		_update_badge_previews(_smart_preview_badge, previews)
		_position_skill_badge(_smart_preview_badge, target_pos)
	else:
		_clear_smart_preview_badge()
		_smart_preview_badge = _create_skill_badge(
			hero, skill, skill_index, tint, "WILL USE", previews)
		_smart_preview_badge.set_meta("skill_index", skill_index)
		_smart_cast_key = cast_key
		if _screen_popup_layer:
			_screen_popup_layer.add_child(_smart_preview_badge)
			_position_skill_badge(_smart_preview_badge, target_pos)
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
	_active_actor_tween.tween_property(_active_actor_ring, "scale", Vector2(1.08, 1.08), 0.35)
	_active_actor_tween.tween_property(_active_actor_ring, "scale", Vector2(1.0, 1.0), 0.35)

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

func spawn_move_ghost(grid_pos: Vector2i, grid: Node, unit_color: Color = Color(0.5, 0.85, 1.0, 0.45)) -> void:
	var ghost := ColorRect.new()
	ghost.color = unit_color
	ghost.size = Vector2(TILE_SIZE - 4, TILE_SIZE - 4)
	ghost.position = grid.grid_to_world(grid_pos) - Vector2(TILE_SIZE / 2.0 - 2, TILE_SIZE / 2.0 - 2)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = 3
	highlight_layer.add_child(ghost)
	_move_ghosts.append(ghost)
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.35)
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
	skull.text = "☠"
	skull.add_theme_font_size_override("font_size", 22)
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

func show_status_indicators(counter_heroes: Array, linked_pairs: Array, grid: Node) -> void:
	_free_list(_status_icons)
	for hero in counter_heroes:
		if not is_instance_valid(hero):
			continue
		_add_status_icon(hero, "🛡", Color(0.3, 0.9, 0.5), grid)
	for pair in linked_pairs:
		if pair.size() < 2:
			continue
		for hero in pair:
			if is_instance_valid(hero):
				_add_status_icon(hero, "🔗", Color(0.5, 0.85, 1.0), grid)

func _add_status_icon(unit: Node, icon_text: String, color: Color, _grid: Node) -> void:
	if not unit is Unit:
		return
	var lbl := Label.new()
	lbl.text = icon_text
	lbl.modulate = color
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _screen_popup_layer:
		_screen_popup_layer.add_child(lbl)
		lbl.position = _place_popup_near_tile(unit.grid_pos, Vector2(20, 18))
	_status_icons.append(lbl)

func clear_highlights() -> void:
	_free_list(_move_highlights)
	_free_list(_skill_range_highlights)
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
