class_name SkillData extends Resource

enum TargetType { ENEMY_SINGLE, ENEMY_AOE, ALLY_SINGLE, SELF }

const SLOT_ATTACK_TINTS: Array[Color] = [
	Color(0.95, 0.32, 0.32, 1.0),
	Color(0.95, 0.58, 0.18, 1.0),
	Color(0.72, 0.38, 0.95, 1.0),
]
const HEAL_TINT: Color = Color(0.28, 0.95, 0.52, 1.0)
const BUFF_TINT: Color = Color(0.42, 0.72, 1.0, 1.0)

@export var id: StringName
@export var display_name: String
@export var description: String
@export var icon: Texture2D
@export var icon_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var range: int = 1
@export var base_damage: float = 10.0
@export var target_type: TargetType = TargetType.ENEMY_SINGLE
@export var attack_type_override: WeaponTriangle.Type = WeaponTriangle.Type.MELEE
@export var use_type_override: bool = false
# Radius of effect around the clicked tile (only used for ENEMY_AOE)
@export var aoe_radius: int = 1
@export var mana_cost: int = 2
@export var grade: int = 1

# Damage/heal magnitude scales by grade^2 (grade 1 = x1); sign preserved so
# healing skills (base_damage < 0) scale too. Range/AoE/mana cost stay fixed.
func eff_damage() -> float:
	return base_damage * Grade.stat_mult(grade)

func get_display_tint(skill_index: int = 0) -> Color:
	if base_damage < 0:
		return HEAL_TINT
	if target_type == TargetType.SELF:
		return BUFF_TINT
	if target_type == TargetType.ALLY_SINGLE and base_damage <= 0:
		return BUFF_TINT
	return SLOT_ATTACK_TINTS[skill_index % SLOT_ATTACK_TINTS.size()]

func is_healing() -> bool:
	return base_damage < 0

func is_buff() -> bool:
	return target_type == TargetType.SELF or (target_type == TargetType.ALLY_SINGLE and base_damage <= 0)
