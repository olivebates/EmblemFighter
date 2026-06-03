class_name BattleManager
extends Node

enum State { HERO_TURN, ENEMY_TURN, GAME_OVER, PLACEMENT }
enum HeroPhase { AWAIT_MOVE, AWAIT_SKILL_SELECT, AWAIT_SKILL }
enum SkillState { AVAILABLE, NO_RANGE, USED }

signal state_changed(new_state: State)
signal placement_started
signal hero_activated(hero: HeroUnit)
signal hero_skills_updated(hero: HeroUnit)
signal victory_achieved
signal movement_tiles_updated(tiles: Array)
signal skill_targets_updated(tiles: Array)
signal skill_valid_targets_updated(tiles: Array)
signal radial_menu_requested(hero_pos: Vector2, skills: Array, states: Array)
signal skill_bar_requested(hero: HeroUnit, states: Array, highlight_index: int)
signal active_skill_changed(hero: HeroUnit, skill: SkillData)
signal turn_order_updated(units: Array)
signal milestone_updated(text: String)
signal status_indicators_updated(counter_heroes: Array, linked_pairs: Array)
signal enemy_telegraph_requested(enemy: EnemyUnit, dest: Vector2i, target: Unit)
signal enemy_telegraph_cleared
signal active_actor_changed(unit: Unit)
signal turn_intent_updated(text: String)
signal move_ghost_at(grid_pos: Vector2i, is_hero: bool)
var state: State = State.HERO_TURN
var hero_phase: HeroPhase = HeroPhase.AWAIT_MOVE
var grid: Grid
var units_layer: Node2D
var hud: BattleHUD = null

var hero_units: Array[HeroUnit] = []
var enemy_units: Array[EnemyUnit] = []
var _heroes_done: Array[HeroUnit] = []
var _turn_queue: Array = []
var _cycle_count: int = 0

var active_hero: HeroUnit = null
var _current_skill_index: int = -1
var _processing: bool = false
var _last_skill_by_hero: Dictionary = {}
var smart_skill_preference: int = -1
var _enemy_wave_size: int = 0
var _enemy_wave_respawn_scheduled: bool = false
var _selected_placement_hero: HeroUnit = null

var _unit_scene := preload("res://battle/units/Unit.tscn")
var _hero_script := preload("res://battle/units/HeroUnit.gd")
var _enemy_script := preload("res://battle/units/EnemyUnit.gd")

func setup(p_grid: Grid, p_units_layer: Node2D, p_hud: BattleHUD = null) -> void:
	grid = p_grid
	units_layer = p_units_layer
	hud = p_hud
	Combat.unit_died.connect(_on_unit_died)
	Combat.damage_dealt.connect(_on_combat_damage_dealt)
	Combat.passive_triggered.connect(_on_passive_triggered)
	_spawn_units()
	_begin_placement()

func _get_hero_spawn_positions(count: int) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var room = RoomLibrary.active_room as RoomData
	if room != null:
		var rect = room.hero_spawn
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for y in range(rect.position.y, rect.position.y + rect.size.y):
				var pos = Vector2i(x, y)
				if grid.is_in_bounds(pos) and grid.is_passable(pos):
					candidates.append(pos)
	# Fallback: bottom half of grid
	if candidates.size() < count:
		for x in range(grid.GRID_W):
			for y in range(grid.GRID_H / 2, grid.GRID_H):
				var pos = Vector2i(x, y)
				if grid.is_in_bounds(pos) and grid.is_passable(pos) and not candidates.has(pos):
					candidates.append(pos)
	candidates.shuffle()
	var result: Array[Vector2i] = []
	for i in mini(count, candidates.size()):
		result.append(candidates[i])
	return result

func _spawn_units() -> void:
	# Seed RNG with room index for deterministic hero/enemy placement per level
	seed(RoomLibrary.current_room_index)

	var heroes_to_spawn: Array[HeroData] = []
	for data in Heroes.active_heroes:
		if PlayerInventory.hero_ko.get(data.id, false):
			continue
		heroes_to_spawn.append(data)

	var hero_starts = _get_hero_spawn_positions(heroes_to_spawn.size())
	for i in heroes_to_spawn.size():
		var data = heroes_to_spawn[i]
		var unit = _unit_scene.instantiate()
		unit.set_script(_hero_script)
		units_layer.add_child(unit)
		unit.add_to_group("heroes")
		unit.setup(data)
		var saved_hp = PlayerInventory.hero_hp.get(data.id, -1)
		if saved_hp > 0:
			unit.hp = mini(saved_hp, unit.max_hp)
			unit.update_hp_bar()
		grid.place_unit(unit, hero_starts[i])
		hero_units.append(unit)

	var spawn_tiles = _collect_enemy_spawn_tiles()
	var room = RoomLibrary.active_room as RoomData

	if room != null and not room.enemy_spawns.is_empty():
		# Spawn the enemies defined in the room
		var tile_idx = 0
		for entry in room.enemy_spawns:
			var cfg = entry as EnemySpawnConfig
			if cfg == null or cfg.enemy == null:
				continue
			for _i in cfg.count:
				if tile_idx >= spawn_tiles.size():
					break
				_create_enemy_unit(cfg.enemy, spawn_tiles[tile_idx])
				tile_idx += 1
	else:
		# Fallback: random escalating enemies
		var target_enemy_count = maxi(2, _enemy_wave_size)
		for i in mini(target_enemy_count, spawn_tiles.size()):
			var data = Enemies.pick_random_enemy()
			if data == null:
				break
			_create_enemy_unit(data, spawn_tiles[i])

	_enemy_wave_size = enemy_units.size()

# --- Placement phase ---

func _begin_placement() -> void:
	state = State.PLACEMENT
	state_changed.emit(State.PLACEMENT)
	_selected_placement_hero = null
	movement_tiles_updated.emit([])
	turn_order_updated.emit([])
	skill_bar_requested.emit(null, [], -1)
	radial_menu_requested.emit(Vector2.ZERO, [], [])
	placement_started.emit()

func start_combat() -> void:
	if state != State.PLACEMENT:
		return
	_selected_placement_hero = null
	movement_tiles_updated.emit([])
	_begin_round()

func on_placement_tile_clicked(grid_pos: Vector2i) -> void:
	if state != State.PLACEMENT:
		return
	var unit = grid.get_unit_at(grid_pos)
	if unit != null and unit.is_in_group("heroes"):
		_selected_placement_hero = unit as HeroUnit
		movement_tiles_updated.emit(_get_placement_move_tiles())
		return
	if _selected_placement_hero != null:
		var valid = _get_placement_move_tiles()
		if valid.has(grid_pos):
			grid.move_unit(_selected_placement_hero, grid_pos)
			_selected_placement_hero.position = grid.grid_to_world(grid_pos)
			_selected_placement_hero = null
			movement_tiles_updated.emit([])
		else:
			_selected_placement_hero = null
			movement_tiles_updated.emit([])

func _get_placement_move_tiles() -> Array[Vector2i]:
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
			if grid.is_empty(pos) or grid.get_unit_at(pos) == _selected_placement_hero:
				result.append(pos)
	return result

# --- Round / initiative ---

func _begin_round() -> void:
	_cycle_count += 1
	_apply_cycle_escalation()
	_heroes_done.clear()
	active_hero = null
	_current_skill_index = -1
	smart_skill_preference = -1
	for hero in hero_units:
		if not is_instance_valid(hero) or hero.hp <= 0:
			continue
		hero.modulate = Color(1, 1, 1, 1)
		hero.reset_for_turn()
		hero.regen_mana(1)
		Combat.fire_passive_turn_start(hero)
		var adj := grid.get_adjacent_units(hero.grid_pos, "heroes")
		Combat.fire_passive_adjacency(hero, adj)
	_build_turn_queue()
	_emit_turn_order()
	_update_status_indicators()
	_advance_turn()

func _apply_cycle_escalation() -> void:
	if _cycle_count <= 1 or _cycle_count % 3 != 0:
		return
	for enemy in enemy_units:
		if is_instance_valid(enemy) and enemy.hp > 0:
			enemy.bonus_atk += 1
	milestone_updated.emit("Enemies +1 ATK")

func _build_turn_queue() -> void:
	var all: Array = []
	for h in hero_units:
		if is_instance_valid(h) and h.hp > 0:
			all.append(h)
	for e in enemy_units:
		if is_instance_valid(e) and e.hp > 0:
			all.append(e)
	all.sort_custom(func(a, b): return a.get_spd() > b.get_spd())
	_turn_queue = all

func _living_hero_count() -> int:
	var n := 0
	for h in hero_units:
		if is_instance_valid(h) and h.hp > 0:
			n += 1
	return n

func _emit_turn_order() -> void:
	var upcoming: Array = []
	if active_hero != null and is_instance_valid(active_hero) and active_hero.hp > 0:
		upcoming.append(active_hero)
	for unit in _turn_queue:
		if is_instance_valid(unit) and unit.hp > 0:
			upcoming.append(unit)
	turn_order_updated.emit(upcoming)

func _update_status_indicators() -> void:
	status_indicators_updated.emit(
		Combat.heroes_with_counter(hero_units, enemy_units, grid),
		Combat.linked_hero_pairs(hero_units)
	)

func _advance_turn() -> void:
	_processing = true
	while not _turn_queue.is_empty():
		var unit = _turn_queue[0]
		_turn_queue.remove_at(0)
		if not is_instance_valid(unit) or unit.hp <= 0:
			continue
		if unit.is_in_group("heroes"):
			_processing = false
			state = State.HERO_TURN
			state_changed.emit(State.HERO_TURN)
			_emit_turn_order()
			_update_status_indicators()
			_activate_hero(unit as HeroUnit)
			return
		elif unit.is_in_group("enemies"):
			_update_status_indicators()
			state = State.ENEMY_TURN
			state_changed.emit(State.ENEMY_TURN)
			movement_tiles_updated.emit([])
			skill_targets_updated.emit([])
			skill_valid_targets_updated.emit([])
			radial_menu_requested.emit(Vector2.ZERO, [], [])
			skill_bar_requested.emit(null, [], -1)
			active_skill_changed.emit(null, null)
			_emit_turn_order()
			active_actor_changed.emit(unit)
			await _run_single_enemy_turn(unit as EnemyUnit)
			if state == State.GAME_OVER:
				_processing = false
				return
	_processing = false
	await get_tree().create_timer(0.15).timeout
	_begin_round()

# --- Input ---

func on_tile_clicked(grid_pos: Vector2i, smart_cast: bool = false, move_only: bool = false) -> void:
	if state != State.HERO_TURN or _processing:
		return
	match hero_phase:
		HeroPhase.AWAIT_MOVE:
			if move_only and _is_move_tile(grid_pos):
				_move_active_hero(grid_pos)
				return
			if grid_pos == active_hero.grid_pos:
				movement_tiles_updated.emit([])
				_enter_skill_select_phase()
				return
			if _is_move_tile(grid_pos):
				_move_active_hero(grid_pos)
				return
			var plan := get_smart_cast_plan(grid_pos)
			if plan.skill_index != -1:
				if smart_cast or plan.move_pos != Vector2i(-1, -1):
					_smart_move_and_cast(plan.move_pos, grid_pos, plan.skill_index)
		HeroPhase.AWAIT_SKILL:
			if _current_skill_index >= 0:
				var skill := active_hero.skills[_current_skill_index]
				if _is_valid_skill_target(skill, grid_pos):
					_cast_current_skill(grid_pos)
				else:
					var alt_idx := Combat.find_best_skill_index(
						active_hero, active_hero.grid_pos, grid_pos, grid)
					if alt_idx >= 0:
						_select_skill(alt_idx)
					else:
						cycle_skill(1, grid_pos)

func on_skill_bar_selected(index: int) -> void:
	on_radial_skill_selected(index)

func on_skill_bar_end_pressed() -> void:
	on_radial_end_pressed()

func on_radial_skill_selected(index: int) -> void:
	if state != State.HERO_TURN or active_hero == null or _processing:
		return
	if hero_phase != HeroPhase.AWAIT_SKILL_SELECT and hero_phase != HeroPhase.AWAIT_SKILL:
		return
	_select_skill(index)

func on_radial_end_pressed() -> void:
	if state != State.HERO_TURN or active_hero == null or _processing:
		return
	_mark_hero_done(true)

func get_smart_cast_plan(target_pos: Vector2i) -> Dictionary:
	if active_hero == null:
		return {"skill_index": -1, "move_pos": Vector2i(-1, -1), "target_pos": target_pos}
	return Combat.find_best_move_and_skill(
		active_hero, target_pos, grid, smart_skill_preference)

const NO_TARGET := Vector2i(-9999, -9999)

func _viable_smart_skill_indices(target_pos: Vector2i) -> Array[int]:
	var viable: Array[int] = []
	for i in active_hero.skills.size():
		if active_hero.skill_used(i):
			continue
		if target_pos != NO_TARGET:
			var plan := Combat.find_best_move_and_skill(active_hero, target_pos, grid, i)
			if plan.skill_index < 0:
				continue
		viable.append(i)
	return viable

func cycle_smart_skill(direction: int = 1, target_pos: Vector2i = NO_TARGET) -> void:
	if state != State.HERO_TURN or active_hero == null or _processing:
		return
	if hero_phase != HeroPhase.AWAIT_MOVE:
		return
	var viable := _viable_smart_skill_indices(target_pos)
	if viable.is_empty():
		return
	if smart_skill_preference < 0 or not viable.has(smart_skill_preference):
		smart_skill_preference = viable[0] if direction > 0 else viable[viable.size() - 1]
		return
	var current_pos := viable.find(smart_skill_preference)
	var next_pos := (current_pos + direction) % viable.size()
	if next_pos < 0:
		next_pos += viable.size()
	smart_skill_preference = viable[next_pos]

func cycle_skill(direction: int = 1, context_target: Vector2i = NO_TARGET) -> void:
	if state != State.HERO_TURN or active_hero == null or _processing:
		return
	if hero_phase == HeroPhase.AWAIT_MOVE:
		cycle_smart_skill(direction, context_target)
		return
	if hero_phase != HeroPhase.AWAIT_SKILL:
		return
	var states := _compute_skill_states()
	var available: Array[int] = []
	for i in states.size():
		if states[i] != SkillState.AVAILABLE:
			continue
		if context_target != NO_TARGET and not _is_valid_skill_target(active_hero.skills[i], context_target):
			continue
		available.append(i)
	if available.is_empty():
		return
	if available.size() == 1:
		_select_skill(available[0])
		return
	var current_pos := available.find(_current_skill_index)
	var next_pos := 0 if current_pos == -1 else (current_pos + direction) % available.size()
	if next_pos < 0:
		next_pos += available.size()
	_select_skill(available[next_pos])

# --- Hero turn ---

func _activate_hero(hero: HeroUnit) -> void:
	active_hero = hero
	_current_skill_index = -1
	smart_skill_preference = -1
	hero_phase = HeroPhase.AWAIT_MOVE
	skill_targets_updated.emit([])
	skill_valid_targets_updated.emit([])
	hero_activated.emit(hero)
	active_actor_changed.emit(hero)
	_show_move_highlights()
	skill_bar_requested.emit(null, [], -1)
	active_skill_changed.emit(null, null)

func _show_move_highlights() -> void:
	if active_hero == null:
		return
	movement_tiles_updated.emit(Combat.get_movement_tiles(active_hero, grid))

func _end_move_phase() -> void:
	if active_hero != null:
		active_hero.movement_remaining = 0

func _move_active_hero(to: Vector2i) -> void:
	var dist := Utils.manhattan(active_hero.grid_pos, to)
	if dist > active_hero.movement_remaining:
		return
	_processing = true
	var from_pos := active_hero.grid_pos
	active_hero.movement_remaining -= dist
	grid.move_unit(active_hero, to)
	move_ghost_at.emit(from_pos, true)
	var tween := active_hero.move_to_world(grid.grid_to_world(to))
	movement_tiles_updated.emit([])
	await tween.finished
	if is_instance_valid(active_hero) and hud:
		hud.update_active_actor_position(active_hero, grid)
	_processing = false
	_update_status_indicators()
	_enter_skill_select_phase()

func _enter_skill_select_phase() -> void:
	if active_hero == null:
		return
	_end_move_phase()
	skill_targets_updated.emit([])
	skill_valid_targets_updated.emit([])
	var states := _compute_skill_states()
	var all_done := true
	for s in states:
		if s == SkillState.AVAILABLE:
			all_done = false
			break
	if all_done:
		_mark_hero_done(false)
		return
	var in_range: Array[int] = []
	for i in states.size():
		if states[i] == SkillState.AVAILABLE:
			var skill: SkillData = active_hero.skills[i]
			if Combat.skill_usable_from(active_hero, skill, active_hero.grid_pos, grid):
				in_range.append(i)
	if not in_range.is_empty():
		var idx := _pick_auto_skill_index(in_range)
		if idx >= 0:
			_select_skill(idx)
		return
	_mark_hero_done(false)

func _pick_auto_skill_index(candidates: Array[int]) -> int:
	var last_idx := int(_last_skill_by_hero.get(active_hero.get_instance_id(), -1))
	if last_idx >= 0 and candidates.has(last_idx):
		return last_idx
	var best_idx := -1
	var best_score := -1.0
	for i in candidates:
		var skill: SkillData = active_hero.skills[i]
		var score := _score_skill_availability(skill)
		if score > best_score:
			best_score = score
			best_idx = i
	return best_idx

func _select_skill(index: int) -> void:
	if active_hero == null or active_hero.skill_used(index):
		return
	var skill := active_hero.skills[index]
	if not Combat.skill_usable_from(active_hero, skill, active_hero.grid_pos, grid):
		return
	_current_skill_index = index
	hero_phase = HeroPhase.AWAIT_SKILL
	movement_tiles_updated.emit([])
	skill_targets_updated.emit(Combat.get_skill_target_tiles(skill, active_hero.grid_pos, grid))
	skill_valid_targets_updated.emit(Combat.get_hittable_tiles(active_hero, skill, grid))
	skill_bar_requested.emit(active_hero, _compute_skill_states(), index)
	active_skill_changed.emit(active_hero, skill)

func _pick_auto_skill(states: Array) -> int:
	var available: Array[int] = []
	for i in states.size():
		if states[i] == SkillState.AVAILABLE:
			available.append(i)
	return _pick_auto_skill_index(available)

func _score_skill_availability(skill: SkillData) -> float:
	if not Combat.skill_usable_from(active_hero, skill, active_hero.grid_pos, grid):
		var positions := Combat.get_movement_tiles(active_hero, grid)
		positions.append(active_hero.grid_pos)
		var best_score := -1.0
		for from_pos in positions:
			if not Combat.skill_usable_from(active_hero, skill, from_pos, grid):
				continue
			var saved_pos := active_hero.grid_pos
			active_hero.grid_pos = from_pos
			var tile := Combat.find_best_target_tile(active_hero, skill, grid)
			active_hero.grid_pos = saved_pos
			if tile == Vector2i(-1, -1):
				continue
			var score := 0.0
			for target in Combat.get_skill_targets_at(active_hero, skill, tile, grid):
				if skill.is_healing():
					score += Combat.preview_heal(active_hero, skill, target).actual_heal
				else:
					var preview := Combat.preview_damage(active_hero, skill, target, grid)
					score += preview.dmg
					if preview.is_kill:
						score += 50.0
			if score > best_score:
				best_score = score
		return best_score
	var tile := Combat.find_best_target_tile(active_hero, skill, grid)
	if tile == Vector2i(-1, -1):
		return -1.0
	var score := 0.0
	for target in Combat.get_skill_targets_at(active_hero, skill, tile, grid):
		if skill.is_healing():
			score += Combat.preview_heal(active_hero, skill, target).actual_heal
		else:
			var preview := Combat.preview_damage(active_hero, skill, target, grid)
			score += preview.dmg
			if preview.is_kill:
				score += 50.0
			if preview.weapon_mult > 1.0:
				score += 8.0
	return score

func get_skill_states() -> Array:
	return _compute_skill_states()

func _compute_skill_states() -> Array:
	var states: Array = []
	for i in active_hero.skills.size():
		if active_hero.skill_used(i):
			states.append(SkillState.USED)
		elif not active_hero.can_afford_skill(active_hero.skills[i]):
			states.append(SkillState.NO_RANGE)
		elif not Combat.can_use_skill_with_movement(active_hero, active_hero.skills[i], grid):
			states.append(SkillState.NO_RANGE)
		else:
			states.append(SkillState.AVAILABLE)
	return states

func _cast_current_skill(target_pos: Vector2i) -> void:
	_processing = true
	skill_targets_updated.emit([])
	skill_valid_targets_updated.emit([])
	skill_bar_requested.emit(active_hero, _compute_skill_states(), _current_skill_index)

	var skill := active_hero.skills[_current_skill_index]
	var target_world := grid.grid_to_world(target_pos)
	var pre_targets := Combat.get_skill_targets_at(active_hero, skill, target_pos, grid)
	if not pre_targets.is_empty():
		target_world = pre_targets[0].position

	var atk_type: WeaponTriangle.Type = skill.attack_type_override
	var has_advantage := false
	for t in pre_targets:
		if WeaponTriangle.get_multiplier(atk_type, t.attack_type) > 1.0:
			has_advantage = true
			break

	var skill_tint := skill.get_display_tint(_current_skill_index)
	var proj_color := Color(skill_tint.r, skill_tint.g, skill_tint.b, 1.0)
	if has_advantage:
		proj_color = Color(1.0, 0.85, 0.2)
	elif skill.is_healing():
		proj_color = skill_tint

	await active_hero.play_attack_windup(target_world)
	active_hero.play_attack_animation(target_world)
	await Utils.launch_projectile(active_hero.position, target_world, proj_color, units_layer)

	if active_hero == null:
		_current_skill_index = -1
		_processing = false
		return

	var used_index := _current_skill_index
	if pre_targets.size() <= 1:
		for target in pre_targets:
			await _apply_skill_hit(active_hero, skill, target)
	else:
		for target in pre_targets:
			await _apply_skill_hit(active_hero, skill, target)
			await get_tree().create_timer(0.08).timeout

	active_hero.spend_mana(skill)
	active_hero.use_skill(used_index)
	_last_skill_by_hero[active_hero.get_instance_id()] = used_index
	_current_skill_index = -1
	if active_hero != null:
		hero_skills_updated.emit(active_hero)
	_processing = false
	_update_status_indicators()

	var states := _compute_skill_states()
	var any_available := false
	for s in states:
		if s == SkillState.AVAILABLE:
			any_available = true
			break
	if not any_available:
		_mark_hero_done(false)
	else:
		hero_phase = HeroPhase.AWAIT_MOVE
		_show_move_highlights()
		skill_bar_requested.emit(null, [], -1)
		active_skill_changed.emit(null, null)

func _is_valid_skill_target(skill: SkillData, target_pos: Vector2i) -> bool:
	if Utils.manhattan(active_hero.grid_pos, target_pos) > skill.range:
		return false
	return not Combat.get_skill_targets_at(active_hero, skill, target_pos, grid).is_empty()

func _mark_hero_done(premature: bool = false) -> void:
	radial_menu_requested.emit(Vector2.ZERO, [], [])
	skill_bar_requested.emit(null, [], -1)
	active_skill_changed.emit(null, null)
	if active_hero and not _heroes_done.has(active_hero):
		_heroes_done.append(active_hero)
		if premature:
			active_hero.modulate = Color(0.35, 0.35, 0.35, 1.0)
	active_hero = null
	_current_skill_index = -1
	movement_tiles_updated.emit([])
	skill_targets_updated.emit([])
	skill_valid_targets_updated.emit([])
	_advance_turn()

func _smart_move_and_cast(move_pos: Vector2i, target_pos: Vector2i, skill_index: int) -> void:
	if skill_index == -1:
		return
	_processing = true
	if move_pos != active_hero.grid_pos:
		var from_pos := active_hero.grid_pos
		var dist := Utils.manhattan(active_hero.grid_pos, move_pos)
		active_hero.movement_remaining -= dist
		grid.move_unit(active_hero, move_pos)
		move_ghost_at.emit(from_pos, true)
		var tween := active_hero.move_to_world(grid.grid_to_world(move_pos))
		movement_tiles_updated.emit([])
		await tween.finished
		if is_instance_valid(active_hero) and hud:
			hud.update_active_actor_position(active_hero, grid)
		_end_move_phase()
	_current_skill_index = skill_index
	_last_skill_by_hero[active_hero.get_instance_id()] = skill_index
	_processing = false
	_cast_current_skill(target_pos)

# --- Enemy turn ---

func _run_single_enemy_turn(enemy: EnemyUnit) -> void:
	var dest := Combat.enemy_move_destination(enemy, hero_units, grid, [])
	var target := enemy.find_attack_target_from(hero_units, dest, true)

	var enemy_name := enemy.label.text if enemy.label else "Enemy"
	if target != null:
		enemy_telegraph_requested.emit(enemy, dest, target)
		await get_tree().create_timer(0.35).timeout
		enemy_telegraph_cleared.emit()
	else:
		pass

	if dest != enemy.grid_pos:
		var enemy_from := enemy.grid_pos
		grid.move_unit(enemy, dest)
		move_ghost_at.emit(enemy_from, false)
		enemy.move_to_world(grid.grid_to_world(dest))
		await get_tree().create_timer(0.22).timeout

	if state == State.GAME_OVER:
		return

	target = enemy.find_attack_target(hero_units, true)
	if target == null:
		_update_status_indicators()
		return

	Utils.floating_text(enemy.get_skill_name(), Color(1.0, 0.5, 0.35), enemy.position + Vector2(0, -24), units_layer, 12)
	await enemy.play_attack_windup(target.position)
	enemy.play_attack_animation(target.position)
	await Utils.launch_projectile(enemy.position, target.position, Color(1.0, 0.35, 0.15), units_layer)

	if not is_instance_valid(target) or target.hp <= 0:
		_update_status_indicators()
		return

	var hp_before := target.hp
	var result := enemy.raw_attack_result(target)
	var enemy_reduction = target.damage_reduction if "damage_reduction" in target else 0.0
	if enemy_reduction > 0.0:
		result.dmg = max(1, int(result.dmg * (1.0 - enemy_reduction)))
	var enemy_block = minf(0.3, target.block_pct) if "block_pct" in target else 0.0
	if enemy_block > 0.0:
		result.dmg = max(1, result.dmg - ceili(result.dmg * enemy_block))
	target.hp -= result.dmg
	target.update_hp_bar()
	var is_lethal := target.hp <= 0 and hp_before > 0
	if is_lethal:
		await _hitstop(0.05)
		if hud:
			await hud.play_kill_flash(target.grid_pos, grid)
		await _hitstop(_hitstop_duration(result.dmg, target, result.is_crit, true))
	elif result.is_crit:
		target.play_crit_hit_animation()
		await _hitstop(_hitstop_duration(result.dmg, target, true, false))
	else:
		target.play_hit_animation()
	_shake_screen_for_hit(result.dmg, target, result.is_crit)
	_show_damage_text(target, result.dmg, result.is_crit, result.weapon_mult)
	Combat.fire_passive_on_damaged(target, enemy, result.dmg)

	if target.hp <= 0:
		Combat.unit_died.emit(target)
		await get_tree().create_timer(0.4).timeout
		_update_status_indicators()
		return

	var counter_skill := Combat.get_hero_counter_skill(target as HeroUnit, enemy)
	if counter_skill != null:
		await get_tree().create_timer(0.1).timeout
		Utils.floating_text("COUNTER!", Color(0.2, 1.0, 0.45), target.position + Vector2(0, -28), units_layer, 16)
		await target.play_attack_windup(enemy.position)
		target.play_attack_animation(enemy.position)
		await Utils.launch_projectile(target.position, enemy.position, Color(0.2, 0.85, 0.4), units_layer)
		if not is_instance_valid(enemy) or enemy.hp <= 0:
			_update_status_indicators()
			return
		var counter_targets := Combat.get_skill_targets_at(target, counter_skill, enemy.grid_pos, grid)
		for ct in counter_targets:
			var cr := Combat.apply_skill_to_target(target, counter_skill, ct, grid)
			if is_instance_valid(ct) and ct.hp > 0:
				if cr.has("is_crit") and cr.is_crit:
					ct.play_crit_hit_animation()
					await _hitstop(0.07)
				else:
					ct.play_hit_animation()
		await get_tree().create_timer(0.12).timeout
	_update_status_indicators()

# --- Damage display & screen shake ---

func _on_passive_triggered(unit: Node, text: String, color: Color) -> void:
	if is_instance_valid(unit):
		Utils.floating_text(text, color, unit.position, units_layer, 13)

func _on_combat_damage_dealt(target: Node, dmg: int, is_crit: bool, weapon_mult: float) -> void:
	if dmg < 0:
		var heal := -dmg
		var size := clampi(12 + heal / 4, 12, 28)
		Utils.floating_text("+%d" % heal, Color(0.2, 1.0, 0.4), target.position, units_layer, size)
	else:
		_show_damage_text(target, dmg, is_crit, weapon_mult)
		if target is Unit:
			_shake_screen_for_hit(dmg, target as Unit, is_crit)

func _apply_skill_hit(caster: HeroUnit, skill: SkillData, target: Node) -> void:
	if not is_instance_valid(target):
		return
	var hp_before = target.hp if "hp" in target else 0
	var grid_pos = target.grid_pos if "grid_pos" in target else Vector2i.ZERO
	var result := Combat.apply_skill_to_target(caster, skill, target, grid)
	if result.has("heal"):
		if target.has_method("play_heal_animation"):
			target.play_heal_animation()
		return
	var dmg: int = result.get("dmg", 0)
	var is_crit: bool = result.get("is_crit", false)
	var is_lethal = hp_before > 0 and is_instance_valid(target) and target.hp <= 0
	if is_lethal:
		await _hitstop(0.05)
		if hud:
			await hud.play_kill_flash(grid_pos, grid)
		await _hitstop(_hitstop_duration(dmg, target as Unit, is_crit, true))
	elif is_crit:
		if is_instance_valid(target) and target.hp > 0:
			target.play_crit_hit_animation()
		await _hitstop(_hitstop_duration(dmg, target as Unit, true, false))
	elif is_instance_valid(target) and target.hp > 0:
		target.play_hit_animation()

func _damage_tier(dmg: int, target: Unit) -> int:
	if target == null:
		return 0
	return Utils.damage_tier(dmg, target.max_hp)

func _hitstop_duration(dmg: int, target: Unit, is_crit: bool, is_kill: bool) -> float:
	var max_hp := target.max_hp if target != null else 0
	return Utils.hitstop_duration(dmg, max_hp, is_crit, is_kill)

func _shake_screen_for_hit(dmg: int, target: Unit, is_crit: bool) -> void:
	var max_hp := target.max_hp if target != null else 0
	Utils.shake_for_hit(units_layer, dmg, max_hp, is_crit)

func _show_damage_text(target: Node, dmg: int, is_crit: bool, weapon_mult: float) -> void:
	var max_hp := (target as Unit).max_hp if target is Unit else 0
	Utils.show_damage_text(target, dmg, is_crit, weapon_mult, units_layer, max_hp)

func _shake_screen(strength: int) -> void:
	Utils.shake_node(units_layer, strength)

func _hitstop(duration: float) -> void:
	await Utils.hitstop(duration)

# --- Death handling ---

func _on_unit_died(unit: Node) -> void:
	if unit.is_in_group("heroes"):
		var hero := unit as HeroUnit
		_turn_queue.erase(hero)
		_heroes_done.erase(hero)
		_last_skill_by_hero.erase(hero.get_instance_id())
		if active_hero == hero:
			radial_menu_requested.emit(Vector2.ZERO, [], [])
			skill_bar_requested.emit(null, [], -1)
			active_skill_changed.emit(null, null)
			active_hero = null
			_current_skill_index = -1
			movement_tiles_updated.emit([])
			skill_targets_updated.emit([])
			skill_valid_targets_updated.emit([])
			if hud:
				hud.clear_active_actor()
		grid.remove_unit(hero)
		var knockback := Vector2(0, -1)
		await hero.play_knocked_out_animation(knockback)
		_update_status_indicators()
		_emit_turn_order()
		if _living_hero_count() == 0:
			await get_tree().create_timer(0.5).timeout
			_game_over(false)
			return
		if state == State.HERO_TURN and active_hero == null:
			call_deferred("_advance_turn")
		return

	grid.remove_unit(unit)

	if unit.is_in_group("enemies"):
		enemy_units.erase(unit as EnemyUnit)
		_turn_queue.erase(unit)
		if enemy_units.is_empty():
			_schedule_enemy_wave_respawn()

	var knockback := Vector2(0, 1)
	await unit.play_death_animation(knockback)
	unit.queue_free()
	_update_status_indicators()

func _schedule_enemy_wave_respawn() -> void:
	if _enemy_wave_respawn_scheduled or state == State.GAME_OVER:
		return
	_enemy_wave_respawn_scheduled = true
	call_deferred("_run_enemy_wave_respawn")

func _run_enemy_wave_respawn() -> void:
	_enemy_wave_respawn_scheduled = false
	if state == State.GAME_OVER or not enemy_units.is_empty() or _living_hero_count() == 0:
		return
	_game_over(true)

func _collect_enemy_spawn_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var room = RoomLibrary.active_room as RoomData
	if room != null:
		var rect = room.enemy_spawn
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for y in range(rect.position.y, rect.position.y + rect.size.y):
				var pos = Vector2i(x, y)
				if grid.is_in_bounds(pos) and grid.is_passable(pos) and grid.is_empty(pos):
					tiles.append(pos)
	# Fallback: top half of grid
	if tiles.is_empty():
		for x in range(grid.GRID_W):
			for y in range(grid.GRID_ROW_MIN, grid.GRID_H / 2):
				var pos = Vector2i(x, y)
				if grid.is_in_bounds(pos) and grid.is_passable(pos) and grid.is_empty(pos):
					tiles.append(pos)
	tiles.shuffle()
	return tiles

func _collect_valid_spawn_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for x in range(grid.GRID_W):
		for y in range(grid.GRID_H):
			var pos := Vector2i(x, y)
			if grid.is_in_bounds(pos) and grid.is_passable(pos) and grid.is_empty(pos):
				tiles.append(pos)
	tiles.shuffle()
	return tiles

func _create_enemy_unit(data: EnemyData, pos: Vector2i) -> EnemyUnit:
	Enemies.ensure_sprite(data)
	var unit := _unit_scene.instantiate()
	unit.set_script(_enemy_script)
	units_layer.add_child(unit)
	unit.add_to_group("enemies")
	unit.setup(data)
	grid.place_unit(unit, pos)
	enemy_units.append(unit as EnemyUnit)
	return unit as EnemyUnit

func _spawn_reinforcement_enemies(count: int) -> void:
	var tiles := _collect_valid_spawn_tiles()
	var to_spawn := mini(count, tiles.size())
	if to_spawn <= 0:
		return
	for i in to_spawn:
		var data := Enemies.pick_random_enemy()
		if data == null:
			break
		_create_enemy_unit(data, tiles[i])
	milestone_updated.emit("Reinforcements +%d" % to_spawn)
	_update_status_indicators()
	_emit_turn_order()

func _game_over(victory: bool) -> void:
	state = State.GAME_OVER
	state_changed.emit(State.GAME_OVER)
	if victory:
		await get_tree().create_timer(0.5).timeout
		PlayerInventory.save_battle_state(hero_units)
		get_tree().paused = true
		victory_achieved.emit()

func start_next_round() -> void:
	for unit in hero_units:
		if is_instance_valid(unit):
			if unit.hp > 0:
				grid.remove_unit(unit)
			unit.queue_free()
	hero_units.clear()
	for unit in enemy_units:
		if is_instance_valid(unit):
			grid.remove_unit(unit)
			unit.queue_free()
	enemy_units.clear()
	_turn_queue.clear()
	_heroes_done.clear()
	active_hero = null
	_current_skill_index = -1
	smart_skill_preference = -1
	_enemy_wave_respawn_scheduled = false
	_enemy_wave_size += 1
	if hud:
		hud.clear_highlights()
		hud.clear_unit_glows()
		hud.clear_active_actor()
		hud.hide_skill_bar()
	# Advance to next room in sequence and reload the grid
	RoomLibrary.pick_next_room()
	grid.reload_room()
	get_tree().paused = false
	_spawn_units()
	_begin_placement()

func _is_move_tile(pos: Vector2i) -> bool:
	return Combat.get_movement_tiles(active_hero, grid).has(pos)
