class_name HeroUnit
extends Unit

var hero_data: HeroData
var skills: Array[SkillData] = []
var passive: PassiveData = null
var equipment: EquipmentData = null

var used_skills: Array[bool] = []
var skill_icons: Array[Texture2D] = []
var movement_remaining: int = 0

func setup(data: HeroData) -> void:
	hero_data = data
	var id := data.id
	skills = Heroes.hero_skills.get(id, [])
	skill_icons = Heroes.hero_skill_icons.get(id, [])
	passive = Heroes.hero_passive.get(id, null)
	equipment = Heroes.hero_equipment.get(id, null)
	used_skills.resize(skills.size())
	used_skills.fill(false)
	init_stats(data.base_hp, data.base_atk, data.base_def, data.base_spd, data.attack_type, data.display_name)
	var sprite: Texture2D = Heroes.hero_sprites.get(id)
	if sprite:
		set_body_sprite(sprite)
	if equipment:
		Equipment.apply_bonuses(self, equipment)
	crit_chance = data.crit_chance
	movement_remaining = get_spd()

func get_passive() -> PassiveData:
	return passive

func get_skill_icon(index: int) -> Texture2D:
	if index >= 0 and index < skill_icons.size():
		return skill_icons[index]
	return null

func all_skills_used() -> bool:
	for used in used_skills:
		if not used:
			return false
	return true

func use_skill(index: int) -> void:
	used_skills[index] = true
	movement_remaining = get_spd()  # reset movement after each skill use

func reset_for_turn() -> void:
	used_skills.fill(false)
	movement_remaining = get_spd()
	reset_temp_stats()

func skill_used(index: int) -> bool:
	if index >= used_skills.size():
		return true
	return used_skills[index]
