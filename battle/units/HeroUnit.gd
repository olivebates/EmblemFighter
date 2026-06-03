class_name HeroUnit
extends Unit

var hero_data: HeroData
var skills: Array[SkillData] = []
var passives: Array[PassiveData] = []
var equipments: Array[EquipmentData] = []

var used_skills: Array[bool] = []
var skill_icons: Array[Texture2D] = []
var movement_remaining: int = 0
var armor_pierce: int = 0
var damage_reduction: float = 0.0
var block_pct: float = 0.0
var mana: int = 10
var max_mana: int = 10

func setup(data: HeroData) -> void:
	hero_data = data
	var id = data.id
	var raw_skills = Heroes.hero_skills.get(id, [])
	skills.assign(raw_skills)
	var raw_icons = Heroes.hero_skill_icons.get(id, [])
	skill_icons.assign(raw_icons)
	var raw_passives = Heroes.hero_passive.get(id, [])
	if raw_passives is Array:
		passives.assign(raw_passives)
	elif raw_passives != null:
		passives = [raw_passives]
	var raw_equips = Heroes.hero_equipment.get(id, [])
	if raw_equips is Array:
		equipments.assign(raw_equips)
	elif raw_equips != null:
		equipments = [raw_equips]
	used_skills.resize(skills.size())
	used_skills.fill(false)
	init_stats(data.base_hp, data.base_atk, data.base_def, data.base_spd, data.attack_type, data.display_name)
	var sprite: Texture2D = Heroes.hero_sprites.get(id)
	if sprite:
		set_body_sprite(sprite)
	for equip in equipments:
		if equip:
			Equipment.apply_bonuses(self, equip)
	crit_chance = data.crit_chance
	movement_remaining = get_spd()
	_apply_op_buff(data)
	var saved_mana = PlayerInventory.hero_mana.get(data.id, -1)
	mana = saved_mana if saved_mana >= 0 else max_mana

func _apply_op_buff(data: HeroData) -> void:
	match data.op_buff_type:
		"atk_flat":
			bonus_atk += int(data.op_buff_value)
		"def_flat":
			bonus_def += int(data.op_buff_value)
		"spd_flat":
			bonus_spd += int(data.op_buff_value)
		"hp_flat":
			max_hp += int(data.op_buff_value)
			hp += int(data.op_buff_value)
			update_hp_bar()
		"crit_always":
			crit_chance = 1.0
		"armor_pierce":
			armor_pierce = int(data.op_buff_value)
		"damage_reduction":
			damage_reduction = data.op_buff_value

# Returns first passive for backward compat (counter check etc.)
func get_passive() -> PassiveData:
	return passives[0] if not passives.is_empty() else null

func get_passives() -> Array[PassiveData]:
	return passives

func get_skill_icon(index: int) -> Texture2D:
	if index >= 0 and index < skill_icons.size():
		return skill_icons[index]
	return null

func can_afford_skill(skill: SkillData) -> bool:
	return mana >= skill.mana_cost

func spend_mana(skill: SkillData) -> void:
	mana = maxi(0, mana - skill.mana_cost)

func regen_mana(amount: int = 1) -> void:
	mana = mini(max_mana, mana + amount)

func all_skills_used() -> bool:
	for used in used_skills:
		if not used:
			return false
	return true

func use_skill(index: int) -> void:
	used_skills[index] = true
	movement_remaining = get_spd()

func reset_for_turn() -> void:
	used_skills.fill(false)
	movement_remaining = get_spd()
	reset_temp_stats()

func skill_used(index: int) -> bool:
	if index >= used_skills.size():
		return true
	return used_skills[index]
