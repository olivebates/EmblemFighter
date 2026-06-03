extends Node

signal skill_executed(caster, targets: Array, damage: int)
signal unit_died(unit)
signal damage_dealt(target: Node, dmg: int, is_crit: bool, weapon_mult: float)
signal passive_triggered(unit: Node, text: String, color: Color)

func resolve_damage(attacker_atk: int, attacker_type: WeaponTriangle.Type,
		defender_def: int, defender_type: WeaponTriangle.Type) -> int:
	var mult = WeaponTriangle.get_multiplier(attacker_type, defender_type)
	return max(0, int((attacker_atk - defender_def) * mult))

func execute_skill(caster: Node, skill: SkillData, target_pos: Vector2i, grid: Node) -> void:
	var targets: Array = _get_targets(caster, skill, target_pos, grid)
	for target in targets:
		apply_skill_to_target(caster, skill, target, grid)
	skill_executed.emit(caster, targets, 0)

func apply_skill_to_target(caster: Node, skill: SkillData, target: Node, grid: Node) -> Dictionary:
	if skill.base_damage < 0:
		var heal := int(abs(skill.eff_damage()))
		target.hp = min(target.hp + heal, target.max_hp)
		target.update_hp_bar()
		damage_dealt.emit(target, -heal, false, 1.0)
		return {heal = heal}
	var result = _skill_damage(caster, skill, target, grid, true)
	var reduction = target.damage_reduction if "damage_reduction" in target else 0.0
	if reduction > 0.0:
		result.dmg = max(1, int(result.dmg * (1.0 - reduction)))
	var blk = minf(0.3, target.block_pct) if "block_pct" in target else 0.0
	if blk > 0.0:
		result.dmg = max(1, result.dmg - ceili(result.dmg * blk))
	target.hp -= result.dmg
	target.update_hp_bar()
	damage_dealt.emit(target, result.dmg, result.is_crit, result.weapon_mult)
	_fire_passive_on_hit(caster, target, result.dmg)
	_fire_passive_on_damaged(target, caster, result.dmg)
	if target.hp <= 0:
		_fire_passive_on_kill(caster, target)
		unit_died.emit(target)
	return result

func preview_damage(caster: Node, skill: SkillData, target: Node, grid: Node) -> Dictionary:
	var values := _compute_damage_values(caster, skill, target, grid)
	var blk = minf(0.3, target.block_pct) if "block_pct" in target else 0.0
	if blk > 0.0:
		values.dmg = max(1, values.dmg - ceili(values.dmg * blk))
	var max_dmg = values.dmg
	if "crit_chance" in caster and caster.crit_chance > 0.0:
		max_dmg = int(values.dmg * 1.5)
	return {
		"dmg": values.dmg,
		"max_dmg": max_dmg,
		"weapon_mult": values.weapon_mult,
		"base_power": values.base_power,
		"def_blocked": values.def_blocked,
		"cover_blocked": values.cover_blocked,
		"is_kill": values.dmg >= target.hp,
		"is_kill_crit": max_dmg >= target.hp,
		"has_cover": values.cover_blocked > 0,
		"cover_bonus": values.cover_blocked,
	}

func preview_heal(_caster: Node, skill: SkillData, target: Node) -> Dictionary:
	var amount := int(abs(skill.eff_damage()))
	var missing = target.max_hp - target.hp
	return {
		"heal": amount,
		"actual_heal": mini(amount, missing),
		"is_heal": true,
		"target": target,
	}

func preview_skill_at(caster: Node, skill: SkillData, target_pos: Vector2i, grid: Node) -> Array:
	var previews: Array = []
	for target in _get_targets(caster, skill, target_pos, grid):
		var p: Dictionary
		if skill.is_healing():
			p = preview_heal(caster, skill, target)
		else:
			p = preview_damage(caster, skill, target, grid)
			p["target"] = target
		if not p.has("target"):
			p["target"] = target
		previews.append(p)
	return previews

func preview_skill_at_from(caster: Node, skill: SkillData, target_pos: Vector2i,
		from_pos: Vector2i, grid: Node) -> Array:
	var saved_pos: Vector2i = caster.grid_pos
	caster.grid_pos = from_pos
	var previews := preview_skill_at(caster, skill, target_pos, grid)
	caster.grid_pos = saved_pos
	return previews

func find_best_skill_index(caster: Node, from_pos: Vector2i, target_pos: Vector2i, grid: Node) -> int:
	if not caster.has_method("skill_used"):
		return -1
	var best_idx := -1
	var best_score := -9999
	for i in caster.skills.size():
		if caster.skill_used(i):
			continue
		var skill: SkillData = caster.skills[i]
		if not _skill_can_hit_from(from_pos, skill, target_pos, caster, grid):
			continue
		var score := _score_skill_at(caster, skill, from_pos, target_pos, grid)
		if score > best_score:
			best_score = score
			best_idx = i
	return best_idx

func find_best_move_and_skill(caster: Node, target_pos: Vector2i, grid: Node,
		preferred_skill_index: int = -1) -> Dictionary:
	var candidates := get_movement_tiles(caster, grid)
	candidates.append(caster.grid_pos)
	var best := {"skill_index": -1, "move_pos": Vector2i(-1, -1), "target_pos": target_pos}
	var best_score := -9999.0
	if preferred_skill_index >= 0 and preferred_skill_index < caster.skills.size():
		if caster.has_method("skill_used") and caster.skill_used(preferred_skill_index):
			return best
		var pref_skill: SkillData = caster.skills[preferred_skill_index]
		for tile in candidates:
			if not _skill_can_hit_from(tile, pref_skill, target_pos, caster, grid):
				continue
			var score := _score_skill_at(caster, pref_skill, tile, target_pos, grid)
			score -= Utils.manhattan(caster.grid_pos, tile) * 0.5
			if score > best_score:
				best_score = score
				best.skill_index = preferred_skill_index
				best.move_pos = tile
		return best
	for tile in candidates:
		var idx := find_best_skill_index(caster, tile, target_pos, grid)
		if idx == -1:
			continue
		var skill: SkillData = caster.skills[idx]
		var score := _score_skill_at(caster, skill, tile, target_pos, grid)
		score -= Utils.manhattan(caster.grid_pos, tile) * 0.5
		if score > best_score:
			best_score = score
			best.skill_index = idx
			best.move_pos = tile
	return best

func find_move_path(from: Vector2i, to: Vector2i, grid: Node, max_steps: int) -> Array[Vector2i]:
	if from == to:
		return [from]
	var came_from: Dictionary = {}
	came_from[from] = Vector2i(-999, -999)
	var queue: Array = [[from, 0]]
	while not queue.is_empty():
		var entry = queue.pop_front()
		var pos: Vector2i = entry[0]
		var dist: int = entry[1]
		if pos == to:
			break
		if dist >= max_steps:
			continue
		for n in _cardinal_neighbors(pos):
			if came_from.has(n) or not grid.is_in_bounds(n):
				continue
			if not grid.is_passable(n):
				continue
			if not grid.is_empty(n) and n != to:
				continue
			came_from[n] = pos
			queue.append([n, dist + 1])
	if not came_from.has(to):
		return [from, to]
	var path: Array[Vector2i] = []
	var cur: Vector2i = to
	while cur != Vector2i(-999, -999):
		path.push_front(cur)
		cur = came_from[cur]
	return path

func heroes_with_counter(heroes: Array, enemies: Array, grid: Node) -> Array:
	var result: Array = []
	for hero in heroes:
		if not is_instance_valid(hero) or hero.hp <= 0:
			continue
		for enemy in enemies:
			if not is_instance_valid(enemy) or enemy.hp <= 0:
				continue
			if Utils.manhattan(hero.grid_pos, enemy.grid_pos) <= enemy.enemy_data.skill_range:
				if _hero_has_counter_skill(hero, enemy):
					result.append(hero)
					break
	return result

func linked_hero_pairs(heroes: Array) -> Array:
	var pairs: Array = []
	for i in heroes.size():
		for j in range(i + 1, heroes.size()):
			var a = heroes[i]
			var b = heroes[j]
			if not is_instance_valid(a) or not is_instance_valid(b):
				continue
			if a.hp <= 0 or b.hp <= 0:
				continue
			if Utils.manhattan(a.grid_pos, b.grid_pos) == 1:
				pairs.append([a, b])
	return pairs

func _hero_has_counter_skill(hero: Node, enemy: Node) -> bool:
	return get_hero_counter_skill(hero, enemy) != null

# Returns the shortest-range single-target damage skill the hero can use to
# retaliate against `enemy` from its current tile, or null if none reaches.
func get_hero_counter_skill(hero: Node, enemy: Node) -> SkillData:
	if hero == null or not is_instance_valid(hero) or not hero.has_method("get_passive"):
		return null
	var dist := Utils.manhattan(hero.grid_pos, enemy.grid_pos)
	var best: SkillData = null
	var best_range := 9999
	for skill in hero.skills:
		if skill.base_damage > 0 and skill.target_type == SkillData.TargetType.ENEMY_SINGLE:
			if skill.range >= dist and skill.range < best_range:
				best = skill
				best_range = skill.range
	return best

func _skill_can_hit_from(from_pos: Vector2i, skill: SkillData, target_pos: Vector2i,
		caster: Node, grid: Node) -> bool:
	if Utils.manhattan(from_pos, target_pos) > skill.range:
		return false
	var saved_pos: Vector2i = caster.grid_pos
	caster.grid_pos = from_pos
	var hits := _get_targets(caster, skill, target_pos, grid)
	caster.grid_pos = saved_pos
	return not hits.is_empty()

func _score_skill_at(caster: Node, skill: SkillData, from_pos: Vector2i,
		target_pos: Vector2i, grid: Node) -> float:
	var saved_pos: Vector2i = caster.grid_pos
	caster.grid_pos = from_pos
	var targets := _get_targets(caster, skill, target_pos, grid)
	var score := 0.0
	for target in targets:
		if skill.is_healing():
			score += preview_heal(caster, skill, target).actual_heal
		else:
			var preview := preview_damage(caster, skill, target, grid)
			score += preview.dmg
			if preview.is_kill:
				score += 50.0
			if preview.weapon_mult > 1.0:
				score += 8.0
	caster.grid_pos = saved_pos
	return score

func skill_usable_from(caster: Node, skill: SkillData, from_pos: Vector2i, grid: Node) -> bool:
	var saved_pos: Vector2i = caster.grid_pos
	caster.grid_pos = from_pos
	var tile := find_best_target_tile(caster, skill, grid)
	caster.grid_pos = saved_pos
	return tile != Vector2i(-1, -1)

func can_use_skill_with_movement(caster: Node, skill: SkillData, grid: Node) -> bool:
	var positions := get_movement_tiles(caster, grid)
	if not positions.has(caster.grid_pos):
		positions.append(caster.grid_pos)
	for from_pos in positions:
		if skill_usable_from(caster, skill, from_pos, grid):
			return true
	return false

func _compute_damage_values(caster: Node, skill: SkillData, target: Node, grid: Node) -> Dictionary:
	# Skill's own attack type drives the weapon triangle — heroes have no inherent type
	var atk_type: WeaponTriangle.Type = skill.attack_type_override
	var base_power = skill.eff_damage() + caster.get_atk()
	var weapon_mult := WeaponTriangle.get_multiplier(atk_type, target.attack_type)
	var after_mult := int(base_power * weapon_mult)
	var pierce = int(caster.armor_pierce) if "armor_pierce" in caster else 0
	var def_blocked = max(0, target.get_def() - pierce)
	var after_def = after_mult - def_blocked
	var cover = grid.get_cover_bonus(target.grid_pos) if grid.has_method("get_cover_bonus") else 0
	var cover_blocked := 0
	if cover > 0 and after_def > 1:
		cover_blocked = mini(cover, after_def - 1)
	var dmg = max(1, after_def - cover)
	return {
		"base_power": base_power,
		"def_blocked": def_blocked,
		"cover_blocked": cover_blocked,
		"weapon_mult": weapon_mult,
		"dmg": dmg,
	}

func _skill_damage(caster: Node, skill: SkillData, target: Node, grid: Node,
		roll_crit: bool = true) -> Dictionary:
	var values := _compute_damage_values(caster, skill, target, grid)
	var result = values.dmg
	var is_crit = false
	if roll_crit and "crit_chance" in caster:
		is_crit = randf() < caster.crit_chance
	if is_crit:
		result = int(result * 1.5)
	return {dmg = result, is_crit = is_crit, weapon_mult = values.weapon_mult}

func get_movement_tiles(unit: Node, grid: Node) -> Array[Vector2i]:
	var origin: Vector2i = unit.grid_pos
	var spd: int = unit.movement_remaining
	var visited: Dictionary = {}
	var queue: Array = [[origin, 0]]
	var result: Array[Vector2i] = []
	while not queue.is_empty():
		var entry = queue.pop_front()
		var pos: Vector2i = entry[0]
		var dist: int = entry[1]
		if visited.has(pos):
			continue
		visited[pos] = true
		if pos != origin:
			result.append(pos)
		if dist >= spd:
			continue
		for neighbor in _cardinal_neighbors(pos):
			if (not visited.has(neighbor) and grid.is_in_bounds(neighbor)
					and grid.is_empty(neighbor) and grid.is_passable(neighbor)):
				queue.append([neighbor, dist + 1])
	return result

func get_skill_target_tiles(skill: SkillData, origin: Vector2i, grid: Node) -> Array[Vector2i]:
	return grid.get_tiles_in_range(origin, skill.range)

func get_skill_targets_at(caster: Node, skill: SkillData, target_pos: Vector2i, grid: Node) -> Array:
	return _get_targets(caster, skill, target_pos, grid)

func enemy_move_destination(enemy: Node, heroes: Array, grid: Node, claimed: Array[Vector2i]) -> Vector2i:
	var origin: Vector2i = enemy.grid_pos
	var spd: int = enemy.get_spd()
	var reachable = _bfs_reachable(origin, spd, grid, claimed)
	if reachable.is_empty():
		return origin
	var best_target: Vector2i = _nearest_hero_pos(origin, heroes)
	var best_pos = origin
	var best_dist = 999999
	for pos in reachable:
		var d = Utils.manhattan(pos, best_target)
		if d < best_dist:
			best_dist = d
			best_pos = pos
	return best_pos

func get_hittable_tiles(caster: Node, skill: SkillData, grid: Node) -> Array[Vector2i]:
	var aoe := skill.aoe_radius if skill.target_type == SkillData.TargetType.ENEMY_AOE else 0
	var result: Array[Vector2i] = []
	for pos in grid.get_tiles_in_range(caster.grid_pos, skill.range + aoe):
		var u = grid.get_unit_at(pos)
		if u == null:
			continue
		match skill.target_type:
			SkillData.TargetType.ENEMY_SINGLE, SkillData.TargetType.ENEMY_AOE:
				if u.is_in_group("enemies"):
					result.append(pos)
			SkillData.TargetType.ALLY_SINGLE:
				if u.is_in_group("heroes") and u != caster:
					result.append(pos)
			SkillData.TargetType.SELF:
				if u == caster:
					result.append(pos)
	return result

func _get_targets(caster: Node, skill: SkillData, target_pos: Vector2i, grid: Node) -> Array:
	var aoe_r: int = skill.aoe_radius if skill.target_type == SkillData.TargetType.ENEMY_AOE else 0
	var candidates: Array = []
	for pos in grid.get_tiles_in_range(target_pos, aoe_r):
		var u = grid.get_unit_at(pos)
		if u == null:
			continue
		match skill.target_type:
			SkillData.TargetType.ENEMY_SINGLE, SkillData.TargetType.ENEMY_AOE:
				if u.is_in_group("enemies"):
					candidates.append(u)
			SkillData.TargetType.ALLY_SINGLE:
				if u.is_in_group("heroes"):
					candidates.append(u)
			SkillData.TargetType.SELF:
				if u == caster:
					candidates.append(u)
	if skill.target_type == SkillData.TargetType.ENEMY_SINGLE:
		var u = grid.get_unit_at(target_pos)
		if u and u.is_in_group("enemies"):
			return [u]
		return []
	if skill.target_type == SkillData.TargetType.ALLY_SINGLE:
		var u = grid.get_unit_at(target_pos)
		if u and u.is_in_group("heroes") and u != caster:
			return [u]
		return []
	return candidates

func _fire_passive_on_hit(caster: Node, target: Node, dmg: int) -> void:
	if not caster.has_method("get_passives"):
		return
	for passive in caster.get_passives():
		if passive == null:
			continue
		match passive.trigger_event:
			PassiveData.TriggerEvent.ON_HIT:
				match passive.effect_type:
					PassiveData.EffectType.COUNTER_ATTACK:
						target.hp -= int(passive.eff_value())
						target.update_hp_bar()
						passive_triggered.emit(caster, "Thorns!", Color(0.9, 0.4, 0.2))
					PassiveData.EffectType.DAMAGE_BOOST:
						caster.temp_atk_bonus += int(passive.eff_value())
						passive_triggered.emit(caster, "+%d ATK" % int(passive.eff_value()), Color(0.4, 0.7, 1.0))

func fire_passive_on_damaged(target: Node, attacker: Node, dmg: int) -> void:
	_fire_passive_on_damaged(target, attacker, dmg)

func _fire_passive_on_damaged(target: Node, attacker: Node, dmg: int) -> void:
	if not target.has_method("get_passives"):
		return
	for passive in target.get_passives():
		if passive == null or passive.trigger_event != PassiveData.TriggerEvent.ON_DAMAGED:
			continue
		match passive.effect_type:
			PassiveData.EffectType.COUNTER_ATTACK:
				if is_instance_valid(attacker) and attacker.hp > 0:
					attacker.hp -= int(passive.eff_value())
					attacker.update_hp_bar()
					damage_dealt.emit(attacker, int(passive.eff_value()), false, 1.0)
					passive_triggered.emit(target, "Retaliate!", Color(1.0, 0.5, 0.2))
					if attacker.hp <= 0:
						unit_died.emit(attacker)
			PassiveData.EffectType.STAT_BUFF:
				target.temp_atk_bonus += int(passive.eff_value())
				passive_triggered.emit(target, "+%d ATK" % int(passive.eff_value()), Color(0.4, 0.7, 1.0))
			PassiveData.EffectType.DAMAGE_BOOST:
				target.temp_atk_bonus += int(passive.eff_value())
				passive_triggered.emit(target, "+%d ATK" % int(passive.eff_value()), Color(0.4, 0.7, 1.0))

func _fire_passive_on_kill(caster: Node, _target: Node) -> void:
	if not caster.has_method("get_passives"):
		return
	for passive in caster.get_passives():
		if passive == null:
			continue
		if passive.trigger_event == PassiveData.TriggerEvent.ON_KILL:
			if passive.effect_type == PassiveData.EffectType.DAMAGE_BOOST:
				caster.temp_atk_bonus += int(passive.eff_value())
				passive_triggered.emit(caster, "+%d ATK" % int(passive.eff_value()), Color(1.0, 0.85, 0.2))

func fire_passive_turn_start(unit: Node) -> void:
	if not unit.has_method("get_passives"):
		return
	for passive in unit.get_passives():
		if passive == null:
			continue
		match passive.trigger_event:
			PassiveData.TriggerEvent.ON_TURN_START:
				match passive.effect_type:
					PassiveData.EffectType.REGEN:
						var amount := int(passive.eff_value())
						unit.hp = min(unit.hp + amount, unit.max_hp)
						unit.update_hp_bar()
						passive_triggered.emit(unit, "+%d HP" % amount, Color(0.2, 1.0, 0.5))
						if unit.has_method("play_heal_animation"):
							unit.play_heal_animation()
					PassiveData.EffectType.STAT_BUFF:
						unit.temp_atk_bonus += int(passive.eff_value())
						passive_triggered.emit(unit, "+%d ATK" % int(passive.eff_value()), Color(0.4, 0.7, 1.0))
						if unit.has_method("play_buff_animation"):
							unit.play_buff_animation()

func fire_passive_adjacency(unit: Node, adjacent_allies: Array) -> void:
	if adjacent_allies.is_empty() or not unit.has_method("get_passives"):
		return
	for passive in unit.get_passives():
		if passive == null:
			continue
		if passive.trigger_event == PassiveData.TriggerEvent.ON_ADJACENT_ALLY:
			if passive.effect_type == PassiveData.EffectType.STAT_BUFF:
				unit.temp_atk_bonus += int(passive.eff_value())
				passive_triggered.emit(unit, "Linked! +%d ATK" % int(passive.eff_value()), Color(0.5, 0.9, 1.0))
				if unit.has_method("play_buff_animation"):
					unit.play_buff_animation()

func _bfs_reachable(origin: Vector2i, spd: int, grid: Node, excluded: Array[Vector2i]) -> Array[Vector2i]:
	var visited: Dictionary = {}
	var queue: Array = [[origin, 0]]
	var result: Array[Vector2i] = []
	while not queue.is_empty():
		var entry = queue.pop_front()
		var pos: Vector2i = entry[0]
		var dist: int = entry[1]
		if visited.has(pos):
			continue
		visited[pos] = true
		if pos != origin and not excluded.has(pos):
			result.append(pos)
		if dist >= spd:
			continue
		for n in _cardinal_neighbors(pos):
			if (not visited.has(n) and grid.is_in_bounds(n) and grid.is_empty(n)
					and not excluded.has(n) and grid.is_passable(n)):
				queue.append([n, dist + 1])
	return result

func _nearest_hero_pos(from: Vector2i, heroes: Array) -> Vector2i:
	var best = from
	var best_d = 999999
	for h in heroes:
		var d = Utils.manhattan(from, h.grid_pos)
		if d < best_d:
			best_d = d
			best = h.grid_pos
	return best

func _cardinal_neighbors(pos: Vector2i) -> Array[Vector2i]:
	return [pos + Vector2i(1,0), pos + Vector2i(-1,0), pos + Vector2i(0,1), pos + Vector2i(0,-1)]

func find_best_target_tile(caster: Node, skill: SkillData, grid: Node) -> Vector2i:
	var best_pos := Vector2i(-1, -1)
	var best_count := 0
	for tile in get_skill_target_tiles(skill, caster.grid_pos, grid):
		var hits := get_skill_targets_at(caster, skill, tile, grid)
		if hits.size() > best_count:
			best_count = hits.size()
			best_pos = tile
	return best_pos
