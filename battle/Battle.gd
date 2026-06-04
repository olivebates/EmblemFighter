extends Node2D

@onready var grid: Grid = $Grid
@onready var units_layer: Node2D = $UnitsLayer
@onready var battle_manager: BattleManager = $BattleManager
@onready var hud: BattleHUD = $BattleHUD
@onready var camera: Camera2D = $Camera2D

var _camera_tween: Tween = null
var _camera_start_zoom: float = -1.0
var _victory_menu: VictoryMenu
var _spawn_zone_layer: Node2D = null

# Placement drag state
var _drag_hero: HeroUnit = null
var _drag_snap_pos: Vector2i = Vector2i(-1, -1)
var _drag_start_pos: Vector2i = Vector2i(-1, -1)
var _drag_valid_tiles: Array[Vector2i] = []

func _ready() -> void:
	_victory_menu = VictoryMenu.new()
	add_child(_victory_menu)
	_victory_menu.next_round_pressed.connect(_on_next_round)
	_victory_menu.visibility_changed.connect(_on_victory_menu_visibility_changed)
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
	hud.placement_start_pressed.connect(battle_manager.start_combat)
	_build_spawn_zone_layer()
	battle_manager.setup(grid, units_layer, hud)
	battle_manager.active_skill_changed.connect(_on_active_skill_changed)
	battle_manager.skill_pulse_requested.connect(_on_skill_pulse_requested)
	battle_manager.active_actor_changed.connect(_on_active_actor_changed)
	battle_manager.move_ghost_at.connect(_on_move_ghost_at)
	Combat.unit_died.connect(func(_u): _update_camera())
	_sync_highlight_mode()
	call_deferred("_refresh_placement_ui")
	call_deferred("_update_camera")

func _process(_delta: float) -> void:
	if _drag_hero == null or not is_instance_valid(_drag_hero):
		return
	var mouse_world = get_local_mouse_position()
	var snap = _nearest_drag_tile(mouse_world)
	if snap != _drag_snap_pos:
		_drag_snap_pos = snap
		if snap != Vector2i(-1, -1):
			hud.show_move_highlights([snap], grid)
		else:
			hud.show_move_highlights([], grid)
	if snap != Vector2i(-1, -1):
		var target = grid.grid_to_world(snap)
		_drag_hero.position = _drag_hero.position.lerp(target, 0.32)

func _nearest_drag_tile(mouse_world: Vector2) -> Vector2i:
	var best_dist = INF
	var best = _drag_start_pos
	for pos in _drag_valid_tiles:
		var d = mouse_world.distance_squared_to(grid.grid_to_world(pos))
		if d < best_dist:
			best_dist = d
			best = pos
	return best

func _get_drag_valid_tiles(hero: HeroUnit) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var room = RoomLibrary.active_room as RoomData
	if room == null:
		return result
	var rect = room.hero_spawn
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var pos = Vector2i(x, y)
			if not grid.is_in_bounds(pos) or not grid.is_passable(pos):
				continue
			if grid.is_empty(pos) or grid.get_unit_at(pos) == hero:
				result.append(pos)
	return result

func _start_hero_drag(hero: HeroUnit) -> void:
	_drag_hero = hero
	_drag_start_pos = hero.grid_pos
	_drag_snap_pos = hero.grid_pos
	_drag_valid_tiles = _get_drag_valid_tiles(hero)
	hero.z_index = 10
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(hero, "scale", Vector2(1.14, 1.14), 0.1)

func _end_hero_drag() -> void:
	if _drag_hero == null:
		return
	var hero = _drag_hero
	var snap := _nearest_drag_tile(get_local_mouse_position())
	_drag_hero = null
	_drag_snap_pos = Vector2i(-1, -1)
	_drag_valid_tiles.clear()
	if snap != hero.grid_pos:
		grid.move_unit(hero, snap)
	if hero.has_method("snap_to_tile_center"):
		hero.snap_to_tile_center(grid)
	else:
		hero.position = grid.grid_to_world(snap)
	hero.z_index = 0
	var target_world := grid.grid_to_world(snap)
	var tw = hero.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SPRING)
	tw.tween_property(hero, "position", target_world, 0.28)
	var tw2 = hero.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tw2.tween_property(hero, "scale", Vector2.ONE, 0.32)
	hud.spawn_move_dust(snap, grid, Color(0.35, 0.75, 1.0, 0.45))
	hud.show_move_highlights([], grid)
	if battle_manager.state == BattleManager.State.PLACEMENT:
		call_deferred("_update_camera")

func _refresh_range_glows() -> void:
	hud.clear_unit_glows()

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
	if event is InputEventMouse and hud.is_mouse_over_skill_panel():
		# Let mouse-up still end an active placement drag even over the HUD
		if event is InputEventMouseButton and not event.pressed and _drag_hero != null:
			_end_hero_drag()
		return
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
			hud.clear_smart_attack_preview()
			hud.set_badge_hover_grid(BattleHUD.BADGE_HOVER_UNSET)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if battle_manager.state == BattleManager.State.PLACEMENT:
				if not event.pressed:
					_end_hero_drag()
				elif grid.is_in_bounds(grid.world_to_grid(get_local_mouse_position())):
					var grid_pos := grid.world_to_grid(get_local_mouse_position())
					var unit = grid.get_unit_at(grid_pos)
					if unit != null and unit.is_in_group("heroes"):
						_start_hero_drag(unit as HeroUnit)
				return
			if not event.pressed:
				return
			var grid_pos := grid.world_to_grid(get_local_mouse_position())
			if not grid.is_in_bounds(grid_pos):
				return
			var smart_cast = event.shift_pressed and Skills.SMART_CAST_ENABLED
			var move_only = event.alt_pressed and battle_manager.hero_phase == BattleManager.HeroPhase.AWAIT_MOVE
			battle_manager.on_tile_clicked(grid_pos, smart_cast, move_only)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if battle_manager.state == BattleManager.State.HERO_TURN:
				if battle_manager.hero_phase == BattleManager.HeroPhase.AWAIT_SKILL:
					battle_manager.cancel_skill()
				else:
					battle_manager.on_skill_bar_end_pressed()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_skill_at_mouse(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_skill_at_mouse(1)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_cycle_skill_at_mouse(1)
		elif event.keycode == KEY_SPACE:
			battle_manager.on_skill_bar_end_pressed()
		elif event.keycode == KEY_Q:
			battle_manager.on_skill_bar_selected(0)
		elif event.keycode == KEY_W:
			battle_manager.on_skill_bar_selected(1)
		elif event.keycode == KEY_E:
			battle_manager.on_skill_bar_selected(2)
		elif event.keycode == KEY_R:
			battle_manager.on_skill_bar_selected(3)

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
	if not Skills.SMART_CAST_ENABLED:
		return
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
		hud.set_badge_hover_grid(BattleHUD.BADGE_HOVER_UNSET)
		hud.clear_smart_attack_preview()
		return
	if unit_at.is_in_group("enemies"):
		_show_enemy_smart_preview(hero, grid_pos)
	elif unit_at.is_in_group("heroes") and unit_at != hero:
		_show_ally_smart_preview(hero, unit_at as HeroUnit, grid_pos)
	else:
		hud.clear_smart_attack_preview()
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
	hud.set_badge_hover_grid(grid_pos)
	hud.clear_damage_preview()
	_refresh_range_glows()

func _show_ally_smart_preview(hero: HeroUnit, ally: HeroUnit, grid_pos: Vector2i) -> void:
	var plan := battle_manager.get_smart_cast_plan(grid_pos)
	if plan.skill_index < 0:
		hud.clear_smart_attack_preview()
		return
	var skill := hero.skills[plan.skill_index]
	if not skill.is_healing() and not skill.is_buff():
		hud.clear_smart_attack_preview()
		return
	var move_pos: Vector2i = plan.move_pos
	var previews := Combat.preview_skill_at_from(hero, skill, grid_pos, move_pos, grid)
	if previews.is_empty():
		hud.clear_smart_attack_preview()
		return
	hud.show_smart_attack_preview(
		hero, move_pos, grid_pos, skill, plan.skill_index, grid, [], previews)
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
		var in_direct_range = Utils.manhattan(hero.grid_pos, grid_pos) <= skill.range
		if not in_direct_range:
			# Try showing a move+cast path preview if movement remains
			if hero.movement_remaining > 0:
				var plan = Combat.find_best_move_and_skill(hero, grid_pos, grid, idx)
				if plan.skill_index == idx:
					var move_pos: Vector2i = plan.move_pos
					var previews := Combat.preview_skill_at_from(hero, skill, grid_pos, move_pos, grid)
					var kills: Array[Vector2i] = []
					for p in previews:
						if p.get("is_kill", false):
							kills.append(p.target.grid_pos as Vector2i)
					hud.show_smart_attack_preview(hero, move_pos, grid_pos, skill, idx, grid, kills, previews)
					hud.set_badge_hover_grid(grid_pos)
					hud.update_active_skill_badge_damage(previews)
					return
			hud.clear_smart_attack_preview()
			hud.set_badge_hover_grid(BattleHUD.BADGE_HOVER_UNSET)
			hud.update_active_skill_badge_damage([])
			hud.set_kill_targets([])
			hud.refresh_kill_overlays(grid)
			return
		# In direct range — draw strike line + target overlay (no move line, keep ACTIVE badge)
		var previews := Combat.preview_skill_at(hero, skill, grid_pos, grid)
		if previews.is_empty():
			hud.clear_smart_attack_preview()
			hud.set_badge_hover_grid(BattleHUD.BADGE_HOVER_UNSET)
			hud.update_active_skill_badge_damage([])
			hud.set_kill_targets([])
			hud.refresh_kill_overlays(grid)
			return
		var kill_positions: Array[Vector2i] = []
		if skill.is_healing():
			hud.set_kill_targets([])
			hud.refresh_kill_overlays(grid)
		else:
			for p in previews:
				if p.get("is_kill", false):
					kill_positions.append(p.target.grid_pos)
			hud.set_kill_targets(kill_positions)
			hud.refresh_kill_overlays(grid)
		hud.show_smart_attack_preview(
			hero, hero.grid_pos, grid_pos, skill, idx, grid, kill_positions, previews, true)
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
		if battle_manager.state != BattleManager.State.PLACEMENT:
			hud.hide_skill_bar()
	else:
		hud.hide_radial_menu()
		hud.show_skill_bar(hero, states, highlight_index)

func _on_skill_pulse_requested(in_range_indices: Array[int]) -> void:
	hud.apply_skill_pulse(in_range_indices)

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
	if _drag_hero != null:
		_end_hero_drag()
	hud.hide_radial_menu()
	hud.clear_enemy_telegraph()
	match new_state:
		BattleManager.State.PLACEMENT:
			hud.clear_highlights()
			hud.clear_unit_glows()
			call_deferred("_refresh_placement_ui")
			call_deferred("_update_camera")
		BattleManager.State.HERO_TURN:
			hud.hide_placement_bar()
			hud.hide_skill_bar()
			_clear_spawn_zones()
			hud.show_hero_turn()
			hud.clear_highlights()
		BattleManager.State.ENEMY_TURN:
			hud.hide_placement_bar()
			_clear_spawn_zones()
			hud.show_enemy_turn()
			hud.clear_highlights()
			hud.clear_unit_glows()
			_update_status_counter_highlights()
		BattleManager.State.GAME_OVER:
			hud.hide_placement_bar()
			_clear_spawn_zones()
			hud.show_game_over(battle_manager.enemy_units.is_empty())
			hud.clear_unit_glows()
	_sync_highlight_mode()

func _on_hero_activated(hero: HeroUnit) -> void:
	hud.set_active_actor(hero, grid)
	_sync_highlight_mode()
	_refresh_range_glows()
	call_deferred("_update_camera")

func _on_active_actor_changed(unit: Unit) -> void:
	hud.set_active_actor(unit, grid)

func _on_move_ghost_at(pos: Vector2i, is_hero: bool) -> void:
	var col := Color(0.35, 0.75, 1.0, 0.4) if is_hero else Color(0.95, 0.35, 0.3, 0.4)
	hud.spawn_move_ghost(pos, grid, col)
	hud.spawn_move_dust(pos, grid, col)
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
		var tint := skill.get_display_tint(idx)
		Utils.floating_text(
			skill.display_name, tint, hero.position + Vector2(0, -30), units_layer, 14)
	else:
		hud.clear_active_skill_on_hero()
	_refresh_range_glows()
	if battle_manager.state == BattleManager.State.HERO_TURN and battle_manager.active_hero != null:
		call_deferred("_update_camera")

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
	if battle_manager.state != BattleManager.State.HERO_TURN or battle_manager.active_hero == null:
		hud.hide_skill_bar()
	_sync_highlight_mode()
	_refresh_range_glows()
	if (battle_manager.state == BattleManager.State.HERO_TURN
			or battle_manager.state == BattleManager.State.PLACEMENT):
		call_deferred("_update_camera")

func _on_skill_targets_updated(tiles: Array) -> void:
	var atype = -1
	var is_heal_or_buff = false
	var hero = battle_manager.active_hero
	var skill: SkillData = null
	if hero != null:
		var idx = battle_manager._current_skill_index
		if idx >= 0 and idx < hero.skills.size():
			skill = hero.skills[idx]
			atype = skill.attack_type_override
			is_heal_or_buff = skill.is_healing() or skill.is_buff()
	hud.show_target_highlights(tiles, grid, _skill_tint(), atype, is_heal_or_buff)
	_show_extended_reach(tiles, hero, skill, is_heal_or_buff)
	_sync_highlight_mode()
	_refresh_range_glows()
	if tiles.is_empty():
		hud.show_cursor_aoe([], grid)
	else:
		hud.hide_radial_menu()
	if battle_manager.state == BattleManager.State.HERO_TURN and battle_manager.active_hero != null:
		call_deferred("_update_camera")

func _show_extended_reach(direct_tiles: Array, hero: HeroUnit, skill: SkillData, is_heal: bool) -> void:
	if hero == null or skill == null or hero.movement_remaining <= 0:
		hud.clear_extended_reach_highlights()
		return
	var move_tiles = Combat.get_movement_tiles(hero, grid)
	if move_tiles.is_empty():
		hud.clear_extended_reach_highlights()
		return
	var direct_set: Dictionary = {}
	for t in direct_tiles:
		direct_set[t] = true
	var extended: Array[Vector2i] = []
	var seen: Dictionary = {}
	var saved_pos = hero.grid_pos
	for move_pos in move_tiles:
		hero.grid_pos = move_pos
		for range_tile in Combat.get_skill_target_tiles(skill, move_pos, grid):
			if not direct_set.has(range_tile) and not seen.has(range_tile):
				seen[range_tile] = true
				extended.append(range_tile)
	hero.grid_pos = saved_pos
	hud.show_extended_reach_highlights(extended, grid, is_heal)

func _on_skill_valid_targets_updated(tiles: Array) -> void:
	hud.set_kill_targets([])
	var combined: Array = tiles.duplicate()
	var hero = battle_manager.active_hero
	if hero != null:
		var idx = battle_manager._current_skill_index
		if idx >= 0 and idx < hero.skills.size():
			var skill = hero.skills[idx]
			if skill.is_healing():
				combined = Combat.get_healable_hittable_tiles(hero, skill, grid)
			elif skill.is_buff():
				combined.clear()
				if skill.target_type == SkillData.TargetType.SELF:
					combined.append(hero.grid_pos)
				for unit in battle_manager.hero_units:
					if not is_instance_valid(unit) or unit.hp <= 0:
						continue
					if skill.target_type == SkillData.TargetType.ALLY_SINGLE and unit == hero:
						continue
					if Utils.manhattan(hero.grid_pos, unit.grid_pos) <= skill.range:
						if not combined.has(unit.grid_pos):
							combined.append(unit.grid_pos)
	hud.show_valid_target_highlights(combined, grid)
	_show_walk_to_shoot_highlights(combined)
	_refresh_range_glows()
	if battle_manager.state == BattleManager.State.HERO_TURN and battle_manager.active_hero != null:
		call_deferred("_update_camera")

func _show_walk_to_shoot_highlights(direct_tiles: Array) -> void:
	var hero = battle_manager.active_hero
	if hero == null or battle_manager.hero_phase != BattleManager.HeroPhase.AWAIT_SKILL:
		hud.clear_walk_to_shoot_highlights()
		return
	var idx = battle_manager._current_skill_index
	if idx < 0 or idx >= hero.skills.size():
		hud.clear_walk_to_shoot_highlights()
		return
	if hero.movement_remaining <= 0:
		hud.clear_walk_to_shoot_highlights()
		return
	hud.show_walk_to_shoot_highlights(_collect_walk_to_shoot_tiles(direct_tiles), grid)

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

const CAMERA_MARGIN_X := 96.0
const CAMERA_MARGIN_TOP := 64.0
const CAMERA_MARGIN_BOTTOM := 96.0
const CAMERA_HUD_SHIFT_FACTOR := 0.22
const CAMERA_MAX_ZOOM_OUT_FACTOR := 0.8

func _include_world_pos(min_pos: Vector2, max_pos: Vector2, world: Vector2) -> Array:
	min_pos.x = minf(min_pos.x, world.x)
	min_pos.y = minf(min_pos.y, world.y)
	max_pos.x = maxf(max_pos.x, world.x)
	max_pos.y = maxf(max_pos.y, world.y)
	return [min_pos, max_pos]

func _include_grid_pos(min_pos: Vector2, max_pos: Vector2, grid_pos: Vector2i) -> Array:
	return _include_world_pos(min_pos, max_pos, grid.grid_to_world(grid_pos))

func _include_spawn_rect(min_pos: Vector2, max_pos: Vector2, spawn_rect: Rect2i) -> Array:
	for x in range(spawn_rect.position.x, spawn_rect.position.x + spawn_rect.size.x):
		for y in range(spawn_rect.position.y, spawn_rect.position.y + spawn_rect.size.y):
			var pos := Vector2i(x, y)
			if grid.is_in_bounds(pos):
				var expanded := _include_grid_pos(min_pos, max_pos, pos)
				min_pos = expanded[0]
				max_pos = expanded[1]
	return [min_pos, max_pos]

func _expand_bounds_for_spawn_zones(min_pos: Vector2, max_pos: Vector2) -> Array:
	var room := RoomLibrary.active_room as RoomData
	if room == null:
		return [min_pos, max_pos]
	var expanded := _include_spawn_rect(min_pos, max_pos, room.hero_spawn)
	min_pos = expanded[0]
	max_pos = expanded[1]
	expanded = _include_spawn_rect(min_pos, max_pos, room.enemy_spawn)
	return expanded

func _collect_walk_to_shoot_tiles(direct_tiles: Array) -> Array[Vector2i]:
	var hero = battle_manager.active_hero
	if hero == null or battle_manager.hero_phase != BattleManager.HeroPhase.AWAIT_SKILL:
		return []
	var idx = battle_manager._current_skill_index
	if idx < 0 or idx >= hero.skills.size() or hero.movement_remaining <= 0:
		return []
	var skill = hero.skills[idx]
	var needs_friendly = skill.is_healing() or skill.is_buff()
	var move_tiles = Combat.get_movement_tiles(hero, grid)
	var extended: Array[Vector2i] = []
	var saved_pos = hero.grid_pos
	for move_pos in move_tiles:
		hero.grid_pos = move_pos
		var hit_tiles := (Combat.get_healable_hittable_tiles(hero, skill, grid)
				if skill.is_healing()
				else Combat.get_hittable_tiles(hero, skill, grid))
		for hit_pos in hit_tiles:
			if direct_tiles.has(hit_pos) or extended.has(hit_pos):
				continue
			var unit_at = grid.get_unit_at(hit_pos)
			if unit_at == null or unit_at.hp <= 0:
				continue
			if needs_friendly and unit_at.is_in_group("heroes"):
				if skill.target_type == SkillData.TargetType.ALLY_SINGLE and unit_at == hero:
					continue
				extended.append(hit_pos)
			elif not needs_friendly and unit_at.is_in_group("enemies"):
				extended.append(hit_pos)
	hero.grid_pos = saved_pos
	return extended

func _update_camera() -> void:
	if _camera_start_zoom < 0.0:
		_camera_start_zoom = camera.zoom.x

	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	var expanded: Array

	for unit in _get_living_units():
		expanded = _include_world_pos(min_pos, max_pos, unit.position)
		min_pos = expanded[0]
		max_pos = expanded[1]

	if battle_manager.state == BattleManager.State.PLACEMENT:
		expanded = _expand_bounds_for_spawn_zones(min_pos, max_pos)
		min_pos = expanded[0]
		max_pos = expanded[1]

	if min_pos.x == INF:
		return

	min_pos -= Vector2(CAMERA_MARGIN_X, CAMERA_MARGIN_TOP)
	max_pos += Vector2(CAMERA_MARGIN_X, CAMERA_MARGIN_BOTTOM)

	var box_size := max_pos - min_pos
	box_size.x = maxf(box_size.x, Grid.TILE_SIZE * 2.0)
	box_size.y = maxf(box_size.y, Grid.TILE_SIZE * 2.0)

	var viewport_size := get_viewport_rect().size
	var bottom_chrome := hud.get_bottom_chrome_height() if is_instance_valid(hud) else 88.0
	var usable_h := maxf(viewport_size.y - bottom_chrome, viewport_size.y * 0.5)
	var target_zoom := minf(viewport_size.x / box_size.x, usable_h / box_size.y)
	var min_zoom := _camera_start_zoom * CAMERA_MAX_ZOOM_OUT_FACTOR
	target_zoom = clampf(target_zoom, min_zoom, 1.5)

	var half_vp_h := viewport_size.y / (2.0 * target_zoom)
	var center := Vector2((min_pos.x + max_pos.x) * 0.5, (min_pos.y + max_pos.y) * 0.5)
	center.y += bottom_chrome * CAMERA_HUD_SHIFT_FACTOR / target_zoom
	if center.y - half_vp_h > min_pos.y:
		center.y = min_pos.y + half_vp_h

	if _camera_tween and _camera_tween.is_valid():
		_camera_tween.kill()

	_camera_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_camera_tween.tween_property(camera, "position", center, 0.4)
	_camera_tween.parallel().tween_property(camera, "zoom", Vector2(target_zoom, target_zoom), 0.4)

func _focus_camera_on_unit(unit: Node2D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if _camera_tween and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_camera_tween.tween_property(camera, "position", unit.position, 0.28)

func _build_spawn_zone_layer() -> void:
	_spawn_zone_layer = Node2D.new()
	_spawn_zone_layer.name = "SpawnZones"
	_spawn_zone_layer.z_index = -1
	grid.add_child(_spawn_zone_layer)

func _on_placement_started() -> void:
	get_tree().paused = false
	hud.enter_placement_phase()
	call_deferred("_refresh_placement_ui")
	_draw_spawn_zones()
	_draw_hero_spawn_outline()
	call_deferred("_update_camera")

func _refresh_placement_ui() -> void:
	if battle_manager.state != BattleManager.State.PLACEMENT:
		return
	get_tree().paused = false
	hud.enter_placement_phase()
	hud.call_deferred("enter_placement_phase")

func _on_victory_menu_visibility_changed() -> void:
	if _victory_menu.visible:
		return
	if battle_manager.state != BattleManager.State.PLACEMENT:
		return
	get_tree().paused = false
	hud.enter_placement_phase()
	call_deferred("_refresh_placement_ui")

func _draw_hero_spawn_outline() -> void:
	var room = RoomLibrary.active_room as RoomData
	if room == null:
		return
	var tiles: Array[Vector2i] = []
	var rect = room.hero_spawn
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var pos = Vector2i(x, y)
			if grid.is_in_bounds(pos):
				tiles.append(pos)
	hud.show_spawn_zone_outline(tiles, grid)

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
	_refresh_placement_ui()
	call_deferred("_refresh_placement_ui")
	call_deferred("_update_camera")
