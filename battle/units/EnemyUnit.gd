class_name EnemyUnit
extends Unit

var enemy_data: EnemyData
var movement_remaining: int = 0

func setup(data: EnemyData) -> void:
	enemy_data = data
	init_stats(data.base_hp, data.base_atk, data.base_def, data.base_spd, data.attack_type, data.display_name)
	var sprite: Texture2D = Enemies.enemy_sprites.get(data.id)
	if sprite:
		set_body_sprite(sprite)
	crit_chance = data.crit_chance
	movement_remaining = get_spd()

func get_skill_name() -> String:
	if enemy_data.skill_display_name.is_empty():
		return "Strike"
	return enemy_data.skill_display_name

# Returns the hero this enemy will attack from a given position, or null if none in range.
func find_attack_target_from(heroes: Array, from_pos: Vector2i, use_advantage: bool = false) -> Unit:
	var in_range := []
	for hero in heroes:
		if not is_instance_valid(hero) or hero.hp <= 0:
			continue
		if Utils.manhattan(from_pos, hero.grid_pos) <= enemy_data.skill_range:
			in_range.append(hero)
	if in_range.is_empty():
		return null
	in_range.sort_custom(func(a, b): return a.hp < b.hp)
	return in_range[0]

func find_attack_target(heroes: Array, use_advantage: bool = false) -> Unit:
	return find_attack_target_from(heroes, grid_pos, use_advantage)

func raw_attack_damage(target: Unit) -> int:
	return raw_attack_result(target).dmg

func raw_attack_result(target: Unit) -> Dictionary:
	# Weapon triangle does not apply to enemy attacks — only hero skills have types
	var dmg = max(1, int(enemy_data.skill_base_damage) - target.get_def())
	var is_crit = randf() < crit_chance
	if is_crit:
		dmg = int(dmg * 1.5)
	return {dmg = dmg, is_crit = is_crit, weapon_mult = 1.0}
