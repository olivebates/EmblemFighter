extends Node2D

@onready var grid: Grid = $Grid
@onready var units_layer: Node2D = $UnitsLayer
@onready var battle_manager: BattleManager = $BattleManager
@onready var hud: BattleHUD = $BattleHUD
@onready var camera: Camera2D = $Camera2D

var _camera_tween: Tween = null
var _victory_menu: VictoryMenu
var _spawn_zone_layer: Node2D = null
var _start_combat_btn: Button = null

func _ready() -> void:
	_victory_menu = VictoryMenu.new()
	add_child(_victory_menu)
	_victory_menu.next_round_pressed.connect(_on_next_round)
	battle_manager.victory_achieved.connect(_on_victory)
	battle_manager.state_changed.connect(_on_state_changed)
	battle_manager.hero_activated.connect(_on_hero_activated)
	battle_manager.movement_tiles_updated.connect(_on_movement_tiles_updated)
	battle_manager.skill_targets_updated.connect(_on_skill_targets_updated)
	battle_manager.skill_valid_targets_updated.connect(_on_skill_valid_targets_updated)
	battle_manager.radial_menu_requested.connect(_on_radial_menu_requested)
	battle_manager.skill_bar_requested.connect(_on_skill_bar_requested)
	battle_manager.turn_order_updated.connect(_on_turn_order_updated)
	battle_manager.milestone_updated.connect(_on_milestone_updated)
	battle_manager.status_indicators_updated.connect(_on_status_indicators_updated)
	battle_manager.enemy_telegraph_requested.connect(_on_enemy_telegraph_requested)
	battle_manager.enemy_telegraph_cleared.connect(func(): hud.clear_enemy_telegraph())
	hud.radial_skill_selected.connect(battle_manager.on_radial_skill_selected)
	hud.radial_end_pressed.connect(battle_manager.on_radial_end_pressed)
	hud.radial_skill_hovered.connect(_on_radial_skill_hovered)
	hud.skill_bar_selected.connect(battle_manager.on_skill_bar_selected)
	hud.skill_bar_end_pressed.connect(battle_manager.on_skill_bar_end_pressed)
	hud.set_layout_context(self, grid)
	battle_manager.placement_started.connect(_on_placement_started)
	_build_spawn_zone_layer()
	_build_start_combat_button()
	battle_manager.setup(grid, units_layer, hud)
	battle_manager.active_skill_changed.connect(_on_active_skill_changed)
	battle_manager.active_actor_changed.connect(_on_active_actor_changed)
	battle_manager.move_ghost_at.connect(_on_move_ghost_at)
	Combat.unit_died.connect(func(_u): _update_camera())
	hud.show_hero_turn()
	_sync_highlight_mode()
	call_deferred("_update_camera")

func _refresh_range_glows() -> void:
	if battle_manager.state != BattleManager.State.HERO_TURN:
		hud.clear_unit_glows()
		return
	var hero := battle_manager.active_hero
	if hero == null or hero.hp <= 0:
		hud.clear_unit_glows()
		return
	var glow_units: Array = []
	var seen: Dictionary = {}
	for i in hero.skills.size():
		if hero.skill_used(i):
			continue
		var skill: SkillData = hero.skills[i]
		if not Combat.can_use_skill_with_movement(hero, skill, grid):
			continue
		var cast_positions: Array[Vector2i] = [hero.grid_pos]
		if battle_manager.hero_phase == BattleManager.HeroPhase.AWAIT_MOVE:
			for pos in Combat.get_movement_tiles(hero, grid):
				if not cast_positions.has(pos):
					cast_positions.append(pos)
		var saved_pos := hero.grid_pos
		for cast_pos in cast_positions:
			hero.grid_pos = cast_pos
			for pos in Combat.get_hittable_tiles(hero, skill, grid):
				var unit_at := grid.get_unit_at(pos)
				if unit_at == null or unit_at.hp <= 0 or seen.has(unit_at):
					continue
				seen[unit_at] = true
				glow_units.append(unit_at)
		hero.grid_pos = saved_pos
	if glow_units.is_empty():
		hud.clear_unit_glows()
		return
	var tint := UITheme.HERO_ACCENT
	if battle_manager.hero_phase == BattleManager.HeroPhase.AWAIT_SKILL:
		var idx := battle_manager._current_skill_index
		if idx >= 0 and idx < hero.skills.size():
			tint = hero.skills[idx].get_display_tint(idx)
	hud.show_unit_glows(glow_units, tint, grid)

func _sync_highlight_mode() -> void:
	if battle_manager.state == BattleManager.State.PLACEMENT:
		hud.set_highlight_mode(BattleHUD.HighlightMode.MOVE)
		return
	if battle_manager.state == BattleManager.State.ENEMY_TURN:
		hud.set_highlight_mode(BattleHUD.HighlightMode.ENEMY)
	elif battle_manager.hero_phase == BattleManager.HeroPhase.AWAIT_SKILL:
		hud.set_highlight_mode(BattleHUD.HighlightMode.SKILL)
	elif battle_manager.hero_phase == BattleManager.HeroPhase.AWAIT_MOVE:
		hud.set_highlight_mode(BattleHUD.HighlightMode.MOVE)
	else:
		hud.set_highlight_mode(BattleHUD.HighlightMode.NONE)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var grid_pos := grid.world_to_grid(get_local_mouse_position())
		if grid.is_in_bounds(grid_pos):
			hud.update_hover(grid_pos, grid)
			_update_aoe_preview(grid_pos)
			_update_damage_preview(grid_pos)
			_update_smart_cast_preview(grid_pos)
		else:
			hud.hide_hover()
			hud.show_cursor_aoe([], grid)
			hud.clear_damage_preview()
			hud.set_badge_hover_grid(BattleHUD.BADGE_HOVER_UNSET)
			hud.clear_smart_attack_preview()
			if battle_manager.hero_phase == BattleManager.HeroPhase.AWAIT_MOVE:
				hud.hide_skill_bar()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var grid_pos := grid.world_to_grid(get_local_mouse_position())
			if not grid.is_in_bounds(grid_pos):
				return
			if battle_manager.state == BattleManager.State.PLACEMENT:
				battle_manager.on_placement_tile_clicked(grid_pos)
			else:
				var smart_cast = event.shift_pressed
				var move_only = event.alt_pressed and battle_manager.hero_phase == BattleManager.HeroPhase.AWAIT_MOVE
				battle_manager.on_tile_clicked(grid_pos, smart_cast, move_only)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if battle_manager.state == BattleManager.State.HERO_TURN:
				battle_manager.on_skill_bar_end_pressed()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_skill_at_mouse(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_skill_at_mouse(1)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_cycle_skill_at_mouse(1)
		elif event.keycode == KEY_E:
			battle_manager.on_skill_bar_end_pressed()

func _skill_tint() -> Color:
	var idx := battle_manager._current_skill_index
	if idx >= 0 and battle_manager.active_hero != null:
		return battle_manager.active_hero.skills[idx].get_display_tint(idx)
	return hud.get_active_skill_tint()

func _refresh_smart_preview_at_mouse() -> void:
	if battle_manager.hero_phase != BattleManager.HeroPhase.AWAIT_MOVE:
		return
	var grid_pos := grid.world_to_grid(get_local_mouse_position())
	if grid.is_in_bounds(grid_pos):
		_update_smart_cast_preview(grid_pos)

func _cycle_skill_at_mouse(direction: int) -> void:
	var grid_pos := grid.world_to_grid(get_local_mouse_position())
	var context := BattleManager.NO_TARGET
	if grid.is_in_bounds(grid_pos):
		context = grid_pos
	battle_manager.cycle_skill(direction, context)
	_refresh_smart_preview_at_mouse()

func _update_smart_cast_preview(grid_pos: Vector2i) -> void:
	if battle_manager.hero_phase != BattleManager.HeroPhase.AWAIT_MOVE:
		hud.clear_smart_attack_preview()
		return
	var hero := battle_manager.active_hero
	if hero == null:
		hud.clear_smart_attack_preview()
		return
	var unit_at := grid.get_unit_at(grid_pos)
	if unit_at == null:
		hud.clear_smart_attack_preview()
		hud.hide_skill_bar()
		hud.set_badge_hover_grid(BattleHUD.BADGE_HOVER_UNSET)
		hud.clear_smart_attack_preview()
		return
	if unit_at.is_in_group("enemies"):
		_show_enemy_smart_preview(hero, grid_pos)
	elif unit_at.is_in_group("heroes") and unit_at != hero:
		_show_ally_smart_preview(hero, unit_at as HeroUnit, grid_pos)
	else:
		hud.clear_smart_attack_preview()
		hud.hide_skill_bar()
		hud.set_badge_hover_grid(BattleHUD.BADGE_HOVER_UNSET)
		hud.clear_smart_attack_preview()

func _show_enemy_smart_preview(hero: HeroUnit, grid_pos: Vector2i) -> void:
	var plan := battle_manager.get_smart_cast_plan(grid_pos)
	if plan.skill_index < 0:
		hud.clear_smart_attack_preview()
		return
	var skill := hero.skills[plan.skill_index]
	var move_pos: Vector2i = plan.move_pos
	var kill_positions: Array[Vector2i] = []
	var previews := Combat.preview_skill_at_from(hero, skill, grid_pos, move_pos, grid)
	for p in previews:
		if p.get("is_kill", false):
			kill_positions.append(p.target.grid_pos)
	hud.show_smart_attack_preview(
		hero, move_pos, grid_pos, skill, plan.skill_index, grid, kill_positions, previews)
	hud.show_skill_bar(hero, battle_manager.get_skill_states(), plan.skill_index)
	hud.set_badge_hover_grid(grid_pos)
	hud.clear_damage_preview()
	_refresh_range_glows()

func _show_ally_smart_preview(hero: HeroUnit, ally: HeroUnit, grid_pos: Vector2i) -> void:
	var plan := battle_manager.get_smart_cast_plan(grid_pos)
	if plan.skill_index < 0:
		hud.clear_smart_attack_preview()
		return
	var skill := hero.skills[plan.skill_index]
	if not skill.is_healing():
		hud.clear_smart_attack_preview()
		return
	var move_pos: Vector2i = plan.move_pos
	var previews := Combat.preview_skill_at_from(hero, skill, grid_pos, move_pos, grid)
	if previews.is_empty():
		hud.clear_smart_attack_preview()
		return
	hud.show_smart_attack_preview(
		hero, move_pos, grid_pos, skill, plan.skill_index, grid, [], previews)
	hud.show_skill_bar(hero, battle_manager.get_skill_states(), plan.skill_index)
	hud.set_badge_hover_grid(grid_pos)
	hud.clear_damage_preview()
	_refresh_range_glows()

func _update_aoe_preview(grid_pos: Vector2i) -> void:
	if battle_manager.hero_phase != BattleManager.HeroPhase.AWAIT_SKILL:
		hud.show_cursor_aoe([], grid)
		return
	var idx := battle_manager._current_skill_index
	if idx >= 0 and battle_manager.active_hero != null:
		var skill: SkillData = battle_manager.active_hero.skills[idx]
		if skill.target_type == SkillData.TargetType.ENEMY_AOE:
			var hero_pos := battle_manager.active_hero.grid_pos
			if Utils.manhattan(hero_pos, grid_pos) <= skill.range:
				var tint := skill.get_display_tint(idx)
				var aoe_color := Color(tint.r, tint.g, tint.b, 0.5)
				hud.show_cursor_aoe(grid.get_tiles_in_range(grid_pos, skill.aoe_radius), grid, aoe_color)
				return
	hud.show_cursor_aoe([], grid)

func _update_damage_preview(grid_pos: Vector2i) -> void:
	if battle_manager.state != BattleManager.State.HERO_TURN:
		hud.clear_damage_preview()
		return
	var hero := battle_manager.active_hero
	if hero == null:
		hud.clear_damage_preview()
		return

	if battle_manager.hero_phase == BattleManager.HeroPhase.AWAIT_SKILL:
		hud.clear_damage_preview()
		var idx := battle_manager._current_skill_index
		if idx < 0:
			hud.set_badge_hover_grid(BattleHUD.BADGE_HOVER_UNSET)
			hud.update_active_skill_badge_damage([])
			return
		var skill := hero.skills[idx]
		if Utils.manhattan(hero.grid_pos, grid_pos) > skill.range:
			hud.set_badge_hover_grid(BattleHUD.BADGE_HOVER_UNSET)
			hud.update_active_skill_badge_damage([])
			hud.set_kill_targets([])
			hud.refresh_kill_overlays(grid)
			return
		var previews := Combat.preview_skill_at(hero, skill, grid_pos, grid)
		if previews.is_empty():
			hud.set_badge_hover_grid(BattleHUD.BADGE_HOVER_UNSET)
			hud.update_active_skill_badge_damage([])
			hud.set_kill_targets([])
			hud.refresh_kill_overlays(grid)
			return
		if skill.is_healing():
			hud.set_kill_targets([])
			hud.refresh_kill_overlays(grid)
		else:
			var kill_positions: Array[Vector2i] = []
			for p in previews:
				if p.get("is_kill", false):
					kill_positions.append(p.target.grid_pos)
			hud.set_kill_targets(kill_positions)
			hud.refresh_kill_overlays(grid)
		hud.set_badge_hover_grid(grid_pos)
		hud.update_active_skill_badge_damage(previews)
	elif battle_manager.hero_phase == BattleManager.HeroPhase.AWAIT_MOVE:
		hud.set_badge_hover_grid(grid_pos)
		hud.update_active_skill_badge_damage([])
		hud.clear_damage_preview()
		_refresh_range_glows()
	else:
		hud.clear_damage_preview()
		hud.update_active_skill_badge_damage([])

func _on_radial_menu_requested(hero_pos: Vector2, skills: Array, states: Array) -> void:
	if skills.is_empty():
		hud.hide_radial_menu()
	else:
		hud.show_radial_menu(hero_pos, skills, states)

func _on_skill_bar_requested(hero: HeroUnit, states: Array, highlight_index: int) -> void:
	if hero == null:
		hud.hide_skill_bar()
	else:
		hud.hide_radial_menu()
		hud.show_skill_bar(hero, states, highlight_index)

func _on_turn_order_updated(units: Array) -> void:
	hud.show_turn_order(units)

func _on_milestone_updated(text: String) -> void:
	hud.show_milestone(text)
	if text.begins_with("Reinforcements"):
		call_deferred("_update_camera")

func _on_status_indicators_updated(counter_heroes: Array, linked_pairs: Array) -> void:
	hud.show_status_indicators(counter_heroes, linked_pairs, grid)
	if battle_manager.state == BattleManager.State.ENEMY_TURN:
		hud.show_counter_highlights(counter_heroes, grid)
	else:
		hud.clear_counter_highlights()

func _on_enemy_telegraph_requested(enemy: EnemyUnit, dest: Vector2i, target: Unit) -> void:
	hud.show_enemy_telegraph(enemy, dest, target, grid)

func _on_state_changed(new_state: BattleManager.State) -> void:
	hud.hide_radial_menu()
	hud.clear_enemy_telegraph()
	match new_state:
		BattleManager.State.PLACEMENT:
			hud.clear_highlights()
			hud.hide_skill_bar()
			hud.clear_unit_glows()
		BattleManager.State.HERO_TURN:
			_start_combat_btn.hide()
			_clear_spawn_zones()
			hud.show_hero_turn()
			hud.clear_highlights()
		BattleManager.State.ENEMY_TURN:
			_start_combat_btn.hide()
			_clear_spawn_zones()
			hud.show_enemy_turn()
			hud.clear_highlights()
			hud.clear_unit_glows()
			_update_status_counter_highlights()
		BattleManager.State.GAME_OVER:
			_start_combat_btn.hide()
			_clear_spawn_zones()
			hud.show_game_over(battle_manager.enemy_units.is_empty())
			hud.clear_unit_glows()
	_sync_highlight_mode()

func _on_hero_activated(hero: HeroUnit) -> void:
	hud.set_active_actor(hero, grid)
	_sync_highlight_mode()
	_refresh_range_glows()

func _on_active_actor_changed(unit: Unit) -> void:
	hud.set_active_actor(unit, grid)

func _on_move_ghost_at(pos: Vector2i, is_hero: bool) -> void:
	var col := Color(0.35, 0.75, 1.0, 0.4) if is_hero else Color(0.95, 0.35, 0.3, 0.4)
	hud.spawn_move_ghost(pos, grid, col)
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(self):
		_update_camera()

func _on_active_skill_changed(hero: HeroUnit, skill: SkillData) -> void:
	hud.clear_smart_attack_preview()
	hud.clear_damage_preview()
	_sync_highlight_mode()
	if hero != null and skill != null:
		var idx := battle_manager._current_skill_index
		hud.show_active_skill_on_hero(hero, skill, idx, grid)
	else:
		hud.clear_active_skill_on_hero()
	_refresh_range_glows()

func _on_radial_skill_hovered(index: int) -> void:
	if index < 0 or battle_manager.active_hero == null:
		hud.show_move_skill_preview([], grid)
		return
	var hero := battle_manager.active_hero
	if index >= hero.skills.size():
		hud.show_move_skill_preview([], grid)
		return
	var skill := hero.skills[index]
	var radius := skill.range
	if skill.target_type == SkillData.TargetType.ENEMY_AOE:
		radius += skill.aoe_radius
	hud.show_move_skill_preview(grid.get_tiles_in_range(hero.grid_pos, radius), grid)

func _on_movement_tiles_updated(tiles: Array) -> void:
	hud.show_move_highlights(tiles, grid)
	hud.clear_smart_attack_preview()
	hud.hide_skill_bar()
	_sync_highlight_mode()
	_refresh_range_glows()

func _on_skill_targets_updated(tiles: Array) -> void:
	var atype = -1
	if battle_manager.active_hero != null:
		var idx = battle_manager._current_skill_index
		if idx >= 0 and idx < battle_manager.active_hero.skills.size():
			atype = battle_manager.active_hero.skills[idx].attack_type_override
	hud.show_target_highlights(tiles, grid, _skill_tint(), atype)
	_sync_highlight_mode()
	_refresh_range_glows()
	if tiles.is_empty():
		hud.show_cursor_aoe([], grid)
	else:
		hud.hide_radial_menu()

func _on_skill_valid_targets_updated(tiles: Array) -> void:
	hud.set_kill_targets([])
	hud.show_valid_target_highlights(tiles, grid)
	_refresh_range_glows()

func _update_status_counter_highlights() -> void:
	var counters := Combat.heroes_with_counter(
		battle_manager.hero_units, battle_manager.enemy_units, grid)
	hud.show_counter_highlights(counters, grid)

func _get_living_units() -> Array:
	var units: Array = []
	for hero in battle_manager.hero_units:
		if is_instance_valid(hero) and hero.hp > 0:
			units.append(hero)
	for enemy in battle_manager.enemy_units:
		if is_instance_valid(enemy) and enemy.hp > 0:
			units.append(enemy)
	return units

func _update_camera() -> void:
	var units := _get_living_units()
	if units.is_empty():
		return

	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for unit in units:
		var p = unit.position
		if p.x < min_pos.x: min_pos.x = p.x
		if p.y < min_pos.y: min_pos.y = p.y
		if p.x > max_pos.x: max_pos.x = p.x
		if p.y > max_pos.y: max_pos.y = p.y

	var margin := 96.0
	min_pos -= Vector2(margin, margin)
	max_pos += Vector2(margin, margin)

	var box_size := max_pos - min_pos
	var center := (min_pos + max_pos) * 0.5

	var viewport_size := get_viewport_rect().size
	var target_zoom = min(viewport_size.x / box_size.x, viewport_size.y / box_size.y)
	target_zoom = clamp(target_zoom, 0.3, 1.5)

	if _camera_tween and _camera_tween.is_valid():
		_camera_tween.kill()

	_camera_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_camera_tween.tween_property(camera, "position", center, 0.4)
	_camera_tween.parallel().tween_property(camera, "zoom", Vector2(target_zoom, target_zoom), 0.4)

func _build_spawn_zone_layer() -> void:
	_spawn_zone_layer = Node2D.new()
	_spawn_zone_layer.name = "SpawnZones"
	_spawn_zone_layer.z_index = -1
	grid.add_child(_spawn_zone_layer)

func _build_start_combat_button() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 8
	add_child(canvas)
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	_start_combat_btn = Button.new()
	_start_combat_btn.text = "Start Combat"
	_start_combat_btn.custom_minimum_size = Vector2(160, 30)
	_start_combat_btn.set_anchor_and_offset(SIDE_LEFT, 0.5, -80)
	_start_combat_btn.set_anchor_and_offset(SIDE_TOP, 0, 4)
	_start_combat_btn.set_anchor_and_offset(SIDE_RIGHT, 0.5, 80)
	_start_combat_btn.set_anchor_and_offset(SIDE_BOTTOM, 0, 34)
	UITheme.apply_button_theme(_start_combat_btn, true, 4)
	_start_combat_btn.pressed.connect(func(): battle_manager.start_combat())
	root.add_child(_start_combat_btn)
	_start_combat_btn.hide()

func _on_placement_started() -> void:
	_start_combat_btn.show()
	_draw_spawn_zones()

func _draw_spawn_zones() -> void:
	_clear_spawn_zones()
	var room = RoomLibrary.active_room as RoomData
	if room == null:
		return
	_add_zone_rects(room.hero_spawn, Color(0.3, 0.6, 1.0, 0.22))
	_add_zone_rects(room.enemy_spawn, Color(1.0, 0.3, 0.3, 0.22))

func _add_zone_rects(spawn_rect: Rect2i, color: Color) -> void:
	for x in range(spawn_rect.position.x, spawn_rect.position.x + spawn_rect.size.x):
		for y in range(spawn_rect.position.y, spawn_rect.position.y + spawn_rect.size.y):
			var pos = Vector2i(x, y)
			if not grid.is_in_bounds(pos):
				continue
			var rect = ColorRect.new()
			rect.size = Vector2(Grid.TILE_SIZE, Grid.TILE_SIZE)
			rect.position = grid.grid_to_world(pos) - Vector2(Grid.TILE_SIZE / 2.0, Grid.TILE_SIZE / 2.0)
			rect.color = color
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_spawn_zone_layer.add_child(rect)

func _clear_spawn_zones() -> void:
	if _spawn_zone_layer == null:
		return
	for child in _spawn_zone_layer.get_children():
		child.queue_free()

func _on_victory() -> void:
	_victory_menu.show_menu()

func _on_next_round() -> void:
	battle_manager.start_next_round()
	call_deferred("_update_camera")
